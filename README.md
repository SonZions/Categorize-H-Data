# Categorize-H-Data

Kleines Python-Tool, das Texte aus einer SQLite-Datenbank über die OpenAI-API
kategorisiert und das Ergebnis zurück in die Datenbank schreibt.

- läuft auf Windows ohne Adminrechte (Microsoft-Store-Python oder
  „Nur für mich"-Installer)
- konfigurierbar über `.env` (DB-Pfad, Tabelle/Spalten, Modell, Kategorien)
- verarbeitet mehrere Texte pro API-Aufruf (Batch), wiederholbar bei Abbruch

## Schnellstart

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env        # OPENAI_API_KEY eintragen
python init_db.py             # optional: Beispiel-DB
python categorize.py --dry-run --limit 5
python categorize.py
```

Eine **ausführliche Anleitung** für die Einrichtung auf einem Windows-Rechner
ohne Adminrechte liegt in [`INSTALL.md`](INSTALL.md).

## Dateien

| Datei | Zweck |
|---|---|
| `categorize.py` | Hauptskript: liest unkategorisierte Zeilen, fragt die API, schreibt zurück |
| `init_db.py` | erzeugt eine Beispiel-Datenbank mit 10 Test-Texten |
| `requirements.txt` | Python-Abhängigkeiten (`openai`, `python-dotenv`) |
| `.env.example` | Vorlage für API-Key und Konfiguration |
| `INSTALL.md` | Installations- und Bedienungsanleitung (Deutsch) |
