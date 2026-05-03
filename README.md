# Categorize-H-Data

Klassifiseert Nederlandstalige pathologie-verslagen in een SQLite-database via
de OpenAI-API. Per verslag worden bepaald:

1. **Procedure** — `ERCP` / `EUS` / `onbekend`
2. **Sample type** — `biopt` / `brush` / `gal_aspirate` / `onbekend`
3. **WHO-categorie** (1–7) volgens *The WHO Reporting System for
   Pancreaticobiliary Cytopathology* (2022)
4. **Confidence** in % (0–100) over de WHO-classificatie

De resultaten worden in een aparte tabel `classificatie_resultaten` weggeschreven,
zodat de bron-tabel ongewijzigd blijft en het script herhaalbaar is.

- Draait op Windows zonder adminrechten (Python uit de Microsoft Store of
  python.org „Nur für mich").
- Configureerbaar via `.env`: DB-pad, tabel- en kolomnamen, model, batchgrootte.
- WHO-categorieën staan vast in de code (zijn gestandaardiseerd) en worden
  via JSON-Schema strict mode bij OpenAI afgedwongen.
- Verwerkt meerdere verslagen per API-aanroep (batch); afgebroken runs gewoon
  opnieuw starten — al gedane records worden overgeslagen.

## Schnellstart (Windows, ohne Terminal)

1. Python installieren (Microsoft Store oder python.org, „Nur für mich").
2. `.env.example` zu `.env` kopieren und `OPENAI_API_KEY` eintragen.
3. **`start.bat` doppelklicken** — beim ersten Lauf werden venv und Pakete
   automatisch eingerichtet, danach läuft direkt die Klassifikation.

## Schnellstart (PowerShell)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env        # OPENAI_API_KEY eintragen
python init_db.py             # optional: Beispiel-DB mit Voorbeeldverslag
python categorize.py --dry-run --limit 1
python categorize.py
```

## Tabellen

**Bron** (bestaand, verwacht; pad/naam via `.env` instelbaar):

```sql
CREATE TABLE deelnemers_geaggregeerd (
  Deelnemersnummer TEXT PRIMARY KEY,
  aantal_rijen     INTEGER,
  tekst            TEXT          -- bevat het pathologie-verslag
);
```

> Heeft de tekstkolom een andere naam, zet die in `.env` als `TEXT_COLUMN`.

**Doel** (wordt automatisch aangemaakt):

```sql
CREATE TABLE classificatie_resultaten (
  Deelnemersnummer    TEXT PRIMARY KEY,
  procedure           TEXT,    -- ERCP / EUS / onbekend
  sample_type         TEXT,    -- biopt / brush / gal_aspirate / onbekend
  who_kategorie       TEXT,    -- naam van de WHO-categorie
  who_kategorienummer INTEGER, -- 1–7 (Arabisch)
  confidence          INTEGER, -- 0–100 (%)
  verwerkt_op         TEXT     -- ISO-timestamp
);
```

## Files

| Datei | Zweck |
|---|---|
| `start.bat` | Doppelklick-Start unter Windows: legt venv an, installiert Pakete, startet die Klassifikation |
| `categorize.py` | Hauptskript: liest unverarbeitete Verslagen, ruft die API mit JSON-Schema-Strict, schreibt Ergebnisse |
| `init_db.py` | erzeugt eine Beispiel-DB mit dem Beispiel-Pathologiebericht |
| `requirements.txt` | Python-Abhängigkeiten (`openai`, `python-dotenv`) |
| `.env.example` | Vorlage für API-Key und Konfiguration |
| `INSTALL.md` | Installations- und Bedienungsanleitung |

Eine **ausführliche Anleitung** für die Einrichtung auf einem Windows-Rechner
ohne Adminrechte liegt in [`INSTALL.md`](INSTALL.md).
