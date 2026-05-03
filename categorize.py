"""Kategorisiert Texte aus einer SQLite-Datenbank ueber die OpenAI-API."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "data.db")
TABLE = os.getenv("TABLE_NAME", "texte")
ID_COL = os.getenv("ID_COLUMN", "id")
TEXT_COL = os.getenv("TEXT_COLUMN", "text")
CATEGORY_COL = os.getenv("CATEGORY_COLUMN", "kategorie")
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "10"))
CATEGORIES_FILE = os.getenv("CATEGORIES_FILE", "categories.json")


def load_categories() -> dict[str, str]:
    if not os.path.exists(CATEGORIES_FILE):
        raise FileNotFoundError(
            f"Kategorien-Datei nicht gefunden: {CATEGORIES_FILE}. "
            f"Bitte categories.example.json kopieren und an die eigenen Kategorien anpassen."
        )
    with open(CATEGORIES_FILE, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict) or not data:
        raise ValueError(
            f"{CATEGORIES_FILE} muss ein nicht-leeres JSON-Objekt der Form "
            '{"Kategoriename": "Beschreibung", ...} sein.'
        )
    return {str(k): str(v) for k, v in data.items()}


def fetch_uncategorized(conn: sqlite3.Connection, limit: int | None) -> list[tuple[int, str]]:
    query = (
        f"SELECT {ID_COL}, {TEXT_COL} FROM {TABLE} "
        f"WHERE {CATEGORY_COL} IS NULL OR {CATEGORY_COL} = ''"
    )
    if limit is not None:
        query += f" LIMIT {int(limit)}"
    return list(conn.execute(query))


def build_messages(items: list[tuple[int, str]], categories: dict[str, str]) -> list[dict]:
    katalog = "\n".join(f"- {name}: {beschreibung}" for name, beschreibung in categories.items())
    system = (
        "Du bist ein praeziser Klassifikator fuer medizinische Texte (Health-Daten). "
        "Ordne jedem Text genau eine der unten aufgelisteten Kategorien zu. "
        "Beruecksichtige dabei sowohl die im Text vorkommenden Begriffe und Befunde "
        "als auch eventuell genannte Diagnosen.\n\n"
        f"Kategorien (Name: Beschreibung/Regel):\n{katalog}\n\n"
        "Verwende ausschliesslich Kategorienamen aus dieser Liste, exakt geschrieben "
        "wie oben. Wenn keine Kategorie eindeutig passt, waehle die naheliegendste; "
        "wenn ueberhaupt nichts passt und 'Sonstiges' definiert ist, nimm 'Sonstiges'.\n\n"
        'Antworte NUR mit gueltigem JSON in der Form '
        '{"results":[{"id":<id>,"kategorie":"<kategorie>"}, ...]} '
        "und gib jede angefragte ID genau einmal zurueck."
    )
    user_payload = {"texte": [{"id": i, "text": t} for i, t in items]}
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
    ]


def categorize_batch(
    client: OpenAI, items: list[tuple[int, str]], categories: dict[str, str]
) -> dict[int, str]:
    resp = client.chat.completions.create(
        model=MODEL,
        messages=build_messages(items, categories),
        response_format={"type": "json_object"},
        temperature=0,
    )
    data = json.loads(resp.choices[0].message.content)
    return {int(r["id"]): str(r["kategorie"]) for r in data.get("results", [])}


def categorize_with_retry(
    client: OpenAI,
    items: list[tuple[int, str]],
    categories: dict[str, str],
    retries: int = 3,
) -> dict[int, str]:
    delay = 2
    for attempt in range(1, retries + 1):
        try:
            return categorize_batch(client, items, categories)
        except Exception as exc:
            if attempt == retries:
                raise
            print(f"  Fehler ({exc}). Neuer Versuch in {delay}s ...")
            time.sleep(delay)
            delay *= 2
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Kategorisiert Texte aus SQLite per OpenAI.")
    parser.add_argument("--limit", type=int, default=None, help="nur N Datensaetze verarbeiten")
    parser.add_argument("--dry-run", action="store_true", help="nur ausgeben, nicht speichern")
    args = parser.parse_args()

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("Fehler: OPENAI_API_KEY nicht gesetzt. Bitte .env-Datei pruefen.", file=sys.stderr)
        return 1
    if not os.path.exists(DB_PATH):
        print(f"Fehler: Datenbank nicht gefunden: {DB_PATH}", file=sys.stderr)
        return 1
    try:
        categories = load_categories()
    except (FileNotFoundError, ValueError) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        return 1

    client = OpenAI(api_key=api_key)
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = fetch_uncategorized(conn, args.limit)
        if not rows:
            print("Keine unkategorisierten Datensaetze gefunden.")
            return 0
        print(
            f"{len(rows)} unkategorisierte Datensaetze gefunden. "
            f"Modell: {MODEL}, Batchgroesse: {BATCH_SIZE}, "
            f"{len(categories)} Kategorien aus {CATEGORIES_FILE}."
        )

        valid = set(categories.keys())
        total_batches = (len(rows) + BATCH_SIZE - 1) // BATCH_SIZE
        for batch_idx, start in enumerate(range(0, len(rows), BATCH_SIZE), start=1):
            batch = rows[start:start + BATCH_SIZE]
            print(f"Batch {batch_idx}/{total_batches} ({len(batch)} Texte) ...")
            results = categorize_with_retry(client, batch, categories)
            for id_, _ in batch:
                cat = results.get(id_)
                if cat is None:
                    print(f"  Warnung: keine Kategorie fuer ID {id_}")
                    continue
                if cat not in valid:
                    print(f"  Warnung: ID {id_} bekam unbekannte Kategorie '{cat}' (wird trotzdem geschrieben)")
                if args.dry_run:
                    print(f"  [DRY] {id_} -> {cat}")
                else:
                    conn.execute(
                        f"UPDATE {TABLE} SET {CATEGORY_COL} = ? WHERE {ID_COL} = ?",
                        (cat, id_),
                    )
            if not args.dry_run:
                conn.commit()
        print("Fertig.")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
