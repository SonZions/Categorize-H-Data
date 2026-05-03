# Categorize-H-Data

Klassifiseert Nederlandstalige pathologie-verslagen in een SQLite-database via
de OpenAI-API. Per verslag worden bepaald:

1. **Procedure** — `ERCP` / `EUS` / `onbekend`
2. **Sample type** — `biopt` / `brush` / `gal_aspirate` / `onbekend`
3. **WHO-categorie** (1–7) volgens *The WHO Reporting System for
   Pancreaticobiliary Cytopathology* (2022)
4. **Confidence** in % (0–100) over de WHO-classificatie

## Pure PowerShell — niets te installeren

Het hele project draait in **Windows PowerShell** (5.1, standaard aanwezig op
Windows 10/11). Geen Python, geen pip, geen admin-rechten. De enige externe
afhankelijkheid is de SQLite-bibliotheek (één DLL, ~1.5 MB), die bij de
eerste start automatisch in een `lib/`-map naast het script wordt gedownload.
Niets wordt op systeemniveau geïnstalleerd of gewijzigd.

## Schnellstart

1. Repo herunterladen (ZIP entpacken oder `git clone`).
2. `.env.example` zu `.env` kopieren und `OPENAI_API_KEY` eintragen.
3. **`start.bat` doppelklicken**. Beim ersten Lauf wird die SQLite-DLL nach
   `lib/` heruntergeladen (~1.5 MB), danach läuft direkt die Klassifikation.

Manuell aus PowerShell:

```powershell
.\categorize.ps1 -DryRun -Limit 1   # Testlauf, schreibt nichts
.\categorize.ps1                    # Echtlauf
.\init-db.ps1                       # optional: Beispiel-DB
```

> **Hinweis:** PowerShell blockiert standardmäßig `.ps1`-Skripte. Die
> `start.bat` umgeht das automatisch via `-ExecutionPolicy Bypass`. Wer
> direkt aus PowerShell startet, einmal pro Sitzung:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

## Tabellen

**Quelle** (vorhanden, Pfad/Spalten via `.env` einstellbar):

```sql
CREATE TABLE deelnemers_geaggregeerd (
  Deelnemersnummer TEXT PRIMARY KEY,
  aantal_rijen     INTEGER,
  tekst            TEXT          -- bevat het pathologie-verslag
);
```

> Heißt die Textspalte anders, in `.env` `TEXT_COLUMN` setzen.

**Ziel** (wird automatisch angelegt):

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

Bereits klassifizierte `Deelnemersnummer` werden bei Folgeläufen
übersprungen (Resume-fähig).

## Files

| Datei | Zweck |
|---|---|
| `start.bat` | Doppelklick-Starter; ruft PowerShell mit Bypass-Policy auf |
| `categorize.ps1` | Hauptskript (PowerShell): lädt SQLite-DLL beim ersten Lauf, ruft OpenAI mit JSON-Schema-Strict, schreibt Ergebnisse |
| `init-db.ps1` | erzeugt eine Beispiel-DB mit dem Beispiel-Pathologiebericht |
| `.env.example` | Vorlage für API-Key und Konfiguration |
| `INSTALL.md` | Installations- und Bedienungsanleitung |

Eine **ausführliche Anleitung** liegt in [`INSTALL.md`](INSTALL.md).
