"""Klassifiseert Nederlandstalige pathologie-verslagen voor (mogelijk maligne) distale galwegobstructie.

Per verslag worden bepaald:
  - procedure   (ERCP / EUS / onbekend)
  - sample_type (biopt / brush / gal_aspirate / onbekend)
  - WHO-categorie volgens "The WHO Reporting System for Pancreaticobiliary Cytopathology" (2022)
  - confidence (0-100 %) over de WHO-classificatie
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "data.db")
SOURCE_TABLE = os.getenv("SOURCE_TABLE", "deelnemers_geaggregeerd")
ID_COL = os.getenv("ID_COLUMN", "Deelnemersnummer")
TEXT_COL = os.getenv("TEXT_COLUMN", "tekst")
RESULT_TABLE = os.getenv("RESULT_TABLE", "classificatie_resultaten")
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "5"))

WHO_CATEGORIES: dict[int, tuple[str, str]] = {
    1: (
        "Insufficient / Inadequate / Non-diagnostic",
        "Onvoldoende of niet-diagnostisch materiaal voor een betrouwbare beoordeling.",
    ),
    2: (
        "Benign / Negative for malignancy",
        "Goedaardig; geen aanwijzingen voor maligniteit.",
    ),
    3: (
        "Atypical",
        "Cellulaire afwijkingen die niet voldoen aan criteria voor neoplasie of maligniteit.",
    ),
    4: (
        "Pancreaticobiliary Neoplasm, Low Risk / Low Grade (PaN-Low)",
        "Pancreaticobiliaire neoplasie met laag risico of lage gradering.",
    ),
    5: (
        "Pancreaticobiliary Neoplasm, High Risk / High Grade (PaN-High)",
        "Pancreaticobiliaire neoplasie met hoog risico of hoge gradering.",
    ),
    6: (
        "Suspicious for malignancy",
        "Verdacht voor maligniteit; criteria voor maligniteit zijn niet volledig vervuld.",
    ),
    7: (
        "Malignant",
        "Maligne; cytologisch of histologisch bewijs van maligniteit.",
    ),
}

VALID_CATEGORY_NAMES = [name for name, _ in WHO_CATEGORIES.values()]


def render_categories() -> str:
    return "\n".join(
        f"  {nr}. {name} — {desc}" for nr, (name, desc) in WHO_CATEGORIES.items()
    )


SYSTEM_PROMPT = f"""Je bent een ervaren patholoog-assistent. Je analyseert Nederlandstalige pathologie-verslagen in het kader van mogelijke maligne distale galwegobstructie en classificeert elk verslag op drie aspecten.

Voor elk verslag bepaal je:

1. PROCEDURE — Screen de gehele tekst: gaat het om een ERCP (Endoscopic Retrograde Cholangiopancreatography) of EUS (Endoscopic Ultrasound)? Antwoord met exact "ERCP", "EUS" of "onbekend".

2. SAMPLE_TYPE — Screen de gehele tekst op het soort afgenomen materiaal:
   - "biopt"        (incl. biopsie, naaldbiopt, core needle biopsy)
   - "brush"        (incl. borstel, borstel-cytologie, cytologische borstel)
   - "gal_aspirate" (incl. galaspiraat, gal-aspiraat, bile aspirate, galvocht)
   - "onbekend"     wanneer geen van bovenstaande eenduidig genoemd is.

3. WHO-CATEGORIE — Classificeer de CONCLUSIE van het verslag volgens "The World Health Organization Reporting System for Pancreaticobiliary Cytopathology" (meest recente versie, 2022). Kies precies ÉÉN categorie:
{render_categories()}

   Geef het categorienummer als Arabisch cijfer 1–7 (kategorienummer) en de exacte categorienaam zoals hierboven (kategorie).

4. CONFIDENCE — Geef in procenten (geheel getal 0–100) aan hoe zeker je bent over de WHO-classificatie.

Antwoord UITSLUITEND met geldig JSON volgens het opgegeven schema. Geef voor elke aangevraagde id precies één resultaat-object terug."""


RESPONSE_SCHEMA = {
    "name": "pathologie_classificatie",
    "strict": True,
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["results"],
        "properties": {
            "results": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": [
                        "id",
                        "procedure",
                        "sample_type",
                        "kategorie",
                        "kategorienummer",
                        "confidence",
                    ],
                    "properties": {
                        "id": {"type": "string"},
                        "procedure": {"type": "string", "enum": ["ERCP", "EUS", "onbekend"]},
                        "sample_type": {
                            "type": "string",
                            "enum": ["biopt", "brush", "gal_aspirate", "onbekend"],
                        },
                        "kategorie": {"type": "string", "enum": VALID_CATEGORY_NAMES},
                        "kategorienummer": {"type": "integer", "minimum": 1, "maximum": 7},
                        "confidence": {"type": "integer", "minimum": 0, "maximum": 100},
                    },
                },
            }
        },
    },
}


def ensure_result_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS "{RESULT_TABLE}" (
            "{ID_COL}"          TEXT PRIMARY KEY,
            procedure           TEXT,
            sample_type         TEXT,
            who_kategorie       TEXT,
            who_kategorienummer INTEGER,
            confidence          INTEGER,
            verwerkt_op         TEXT
        )
        """
    )
    conn.commit()


def fetch_pending(conn: sqlite3.Connection, limit: int | None) -> list[tuple[str, str]]:
    query = (
        f'SELECT s."{ID_COL}", s."{TEXT_COL}" '
        f'FROM "{SOURCE_TABLE}" s '
        f'LEFT JOIN "{RESULT_TABLE}" r ON r."{ID_COL}" = s."{ID_COL}" '
        f'WHERE r."{ID_COL}" IS NULL AND s."{TEXT_COL}" IS NOT NULL AND s."{TEXT_COL}" <> \'\''
    )
    if limit is not None:
        query += f" LIMIT {int(limit)}"
    return [(str(i), str(t)) for i, t in conn.execute(query)]


def build_messages(items: list[tuple[str, str]]) -> list[dict]:
    user_payload = {"verslagen": [{"id": i, "tekst": t} for i, t in items]}
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
    ]


def classify_batch(client: OpenAI, items: list[tuple[str, str]]) -> dict[str, dict]:
    resp = client.chat.completions.create(
        model=MODEL,
        messages=build_messages(items),
        response_format={"type": "json_schema", "json_schema": RESPONSE_SCHEMA},
        temperature=0,
    )
    data = json.loads(resp.choices[0].message.content)
    return {str(r["id"]): r for r in data.get("results", [])}


def classify_with_retry(
    client: OpenAI, items: list[tuple[str, str]], retries: int = 3
) -> dict[str, dict]:
    delay = 2
    for attempt in range(1, retries + 1):
        try:
            return classify_batch(client, items)
        except Exception as exc:
            if attempt == retries:
                raise
            print(f"  Fout ({exc}). Nieuwe poging over {delay}s ...")
            time.sleep(delay)
            delay *= 2
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Klassifiseert pathologie-verslagen (ERCP/EUS, sample type, WHO-categorie)."
    )
    parser.add_argument("--limit", type=int, default=None, help="alleen N records verwerken")
    parser.add_argument("--dry-run", action="store_true", help="alleen tonen, niet wegschrijven")
    args = parser.parse_args()

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("Fout: OPENAI_API_KEY niet gezet. Controleer .env.", file=sys.stderr)
        return 1
    if not os.path.exists(DB_PATH):
        print(f"Fout: database niet gevonden: {DB_PATH}", file=sys.stderr)
        return 1

    client = OpenAI(api_key=api_key)
    conn = sqlite3.connect(DB_PATH)
    try:
        ensure_result_table(conn)
        rows = fetch_pending(conn, args.limit)
        if not rows:
            print("Geen openstaande verslagen gevonden.")
            return 0
        print(
            f"{len(rows)} verslagen te verwerken. "
            f"Model: {MODEL}, batch: {BATCH_SIZE}, bron: {SOURCE_TABLE}."
        )

        now_iso = datetime.now(timezone.utc).isoformat(timespec="seconds")
        total_batches = (len(rows) + BATCH_SIZE - 1) // BATCH_SIZE
        for batch_idx, start in enumerate(range(0, len(rows), BATCH_SIZE), start=1):
            batch = rows[start:start + BATCH_SIZE]
            print(f"Batch {batch_idx}/{total_batches} ({len(batch)} verslagen) ...")
            results = classify_with_retry(client, batch)

            for id_, _ in batch:
                r = results.get(id_)
                if not r:
                    print(f"  Waarschuwing: geen resultaat voor {id_}")
                    continue
                line = (
                    f"  {id_}: procedure={r['procedure']}, sample={r['sample_type']}, "
                    f"WHO={r['kategorienummer']} ({r['kategorie']}), "
                    f"confidence={r['confidence']}%"
                )
                if args.dry_run:
                    print("[DRY]" + line)
                else:
                    print(line)
                    conn.execute(
                        f'INSERT OR REPLACE INTO "{RESULT_TABLE}" '
                        f'("{ID_COL}", procedure, sample_type, who_kategorie, '
                        f'who_kategorienummer, confidence, verwerkt_op) '
                        f"VALUES (?, ?, ?, ?, ?, ?, ?)",
                        (
                            id_,
                            r["procedure"],
                            r["sample_type"],
                            r["kategorie"],
                            r["kategorienummer"],
                            r["confidence"],
                            now_iso,
                        ),
                    )
            if not args.dry_run:
                conn.commit()
        print("Klaar.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
