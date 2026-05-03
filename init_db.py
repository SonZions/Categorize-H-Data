"""Maakt een SQLite-database met de bron-tabel deelnemers_geaggregeerd en een voorbeeldverslag."""

import os
import sqlite3

from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "data.db")
SOURCE_TABLE = os.getenv("SOURCE_TABLE", "deelnemers_geaggregeerd")
ID_COL = os.getenv("ID_COLUMN", "Deelnemersnummer")
TEXT_COL = os.getenv("TEXT_COLUMN", "tekst")

VOORBEELD_TEKST = """Datum ontvangst: 21 juni
Datum autorisatie: 31-03

KLINISCHE GEGEVENS:
Klinische gegevens Klinische gegevens: beeld van gemetastaseere maligniteti eci. eerde longkanekrgehad, nu mogelijk pancreas/papilcarcinoom op CT
Indicatie aanvraag: punctie buikwandmetastase

MEtastase eerdere longca?
toch metastase van andere primaire intraabdominaal?
Opmerking van radioloog: punctie buikwand-
Datum onderzoek: 20250829
Tijd onderzoek: :
Restmateriaal onbekend

Inzending I
buikwand
verkrijgingswijze: biopt
Aantal biopten: 2
Zijdighfeid: (para)mediaan
Materiaal buikwand
VERKRIJGING biopt


MACROSCOPIE:
MD) Patient gegevens gecontroleerd
2x naaldbiopten waarvan een zeer flardig van 1,02 sept 2020,6 cm + flardjes, ti.


MICROSCOPIE:
Naaldbiopt, dat deels mechanisch beschadigd is en daardoor morfologisch lastig te beoordelen. Voor zover door verknijping te beoordelen lijkt er sprake van een populatie van atypische lymfoid ogende cellen, die morfologisch sterk overeenkomen met het beeld onder T07-838730 (waarop reeds analyse is ingezet). Op dit biopt door collega reeds aanvullende kleuringen verricht:
-Positief: CD20, matig tot hoge proliferatieve activiteit in Ki-67 (voor zover betrouwbaar te beoordelen als gevolg van verknijping)
-Negatief: CK AE1/3, TTF1.


CONCLUSIE:
Biopten laesie buikwand: tumorpositief, waarbij sprake is van lokalisatie van een maligne B-cellymfoom. Reeds op biopten van elders in het lichaam (papil van Vater, morfologisch hetzelfde beeld) is voor verdere typering analyse ingezet; zie derhalve voor de verdere analyse van het lymfoom de uitslag onder RPA09-962881."""

VOORBEELDEN = [
    ("DLN-0001", 1, VOORBEELD_TEKST),
]


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        f'CREATE TABLE IF NOT EXISTS "{SOURCE_TABLE}" ('
        f'  "{ID_COL}" TEXT PRIMARY KEY,'
        f"   aantal_rijen INTEGER,"
        f'  "{TEXT_COL}" TEXT'
        f")"
    )
    cur = conn.execute(f'SELECT COUNT(*) FROM "{SOURCE_TABLE}"')
    if cur.fetchone()[0] == 0:
        conn.executemany(
            f'INSERT INTO "{SOURCE_TABLE}" ("{ID_COL}", aantal_rijen, "{TEXT_COL}") '
            f"VALUES (?, ?, ?)",
            VOORBEELDEN,
        )
        conn.commit()
        print(f"{len(VOORBEELDEN)} voorbeeldverslag(en) toegevoegd aan {DB_PATH} ({SOURCE_TABLE}).")
    else:
        print(f"Tabel {SOURCE_TABLE} bevat al data – niets toegevoegd.")
    conn.close()


if __name__ == "__main__":
    main()
