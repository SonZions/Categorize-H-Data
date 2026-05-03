"""Erzeugt eine Beispiel-SQLite-Datenbank mit unkategorisierten Texten."""

import os
import sqlite3

from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "data.db")
TABLE = os.getenv("TABLE_NAME", "texte")
ID_COL = os.getenv("ID_COLUMN", "id")
TEXT_COL = os.getenv("TEXT_COLUMN", "text")
CATEGORY_COL = os.getenv("CATEGORY_COLUMN", "kategorie")

BEISPIELE = [
    "Rechnung fuer Stromverbrauch April 2026, faellig zum 15. Mai.",
    "Liebe Anna, ich wuerde Dich gerne zu meinem Geburtstag einladen.",
    "Mietvertrag fuer die Wohnung in der Hauptstrasse 12, 3 Zimmer.",
    "Sonderangebot: 20% Rabatt auf alle Schuhe bis Sonntag!",
    "Bescheid des Finanzamts ueber die Einkommensteuer 2025.",
    "Bestellbestaetigung Amazon: Kabel HDMI 2m, Lieferung am 05.05.",
    "Mahnung wegen ueberfaelliger Telefonrechnung der Vodafone GmbH.",
    "Newsletter: Neue Kurse im Yoga-Studio im Mai.",
    "Versicherungspolice Hausrat, Praemie 142 EUR jaehrlich.",
    "Kassenbeleg REWE 23.04.2026, Summe 47,32 EUR.",
]


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        f"CREATE TABLE IF NOT EXISTS {TABLE} ("
        f"  {ID_COL} INTEGER PRIMARY KEY AUTOINCREMENT,"
        f"  {TEXT_COL} TEXT NOT NULL,"
        f"  {CATEGORY_COL} TEXT"
        f")"
    )
    cur = conn.execute(f"SELECT COUNT(*) FROM {TABLE}")
    if cur.fetchone()[0] == 0:
        conn.executemany(
            f"INSERT INTO {TABLE} ({TEXT_COL}) VALUES (?)",
            [(t,) for t in BEISPIELE],
        )
        conn.commit()
        print(f"{len(BEISPIELE)} Beispieldatensaetze in {DB_PATH} eingefuegt.")
    else:
        print(f"Tabelle {TABLE} enthaelt bereits Daten – nichts eingefuegt.")
    conn.close()


if __name__ == "__main__":
    main()
