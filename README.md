# Categorize-H-Data

Klassifiziert niederländische Pathologieberichte aus einer SQLite-Datenbank
über die OpenAI-API. Pro Bericht werden bestimmt:

1. **Procedure** — `ERCP` / `EUS` / `onbekend`
2. **Sample type** — `biopt` / `brush` / `gal_aspirate` / `onbekend`
3. **WHO-Kategorie** (1–7) gemäß *The WHO Reporting System for
   Pancreaticobiliary Cytopathology* (2022)
4. **Confidence** in % (0–100) zur WHO-Klassifikation

## So einfach geht's

1. ZIP entpacken (oder Repo klonen).
2. **`start.bat` doppelklicken.**
3. Beim allerersten Start fragt das Skript zwei Dinge ab:
   - **API-Key**: in einem Windows-Dialog einfügen (wird gleich getestet).
   - **Datenbank-Datei**: über einen Datei-Auswahldialog anklicken.
   Beides wird in einer `.env`-Datei gespeichert und beim nächsten Start
   nicht mehr abgefragt.
4. Vor der Klassifikation kommt eine Übersicht mit der Frage „Starten? [J/n]".
5. Am Ende eine kurze Zusammenfassung.

Kein Python, kein `pip`, keine Adminrechte, nichts auf Systemebene installiert.
Die SQLite-Bibliothek (~1.5 MB DLL) lädt das Skript einmalig in den
Projektordner herunter.

## Bedienung

| Aktion | Was tun |
|---|---|
| **Klassifikation starten** | `start.bat` doppelklicken |
| **Nur testen, nichts speichern** | aus PowerShell: `.\categorize.ps1 -DryRun -Limit 5` |
| **API-Key oder DB-Pfad ändern** | Datei `.env` im Editor öffnen und Wert anpassen |
| **Komplett neu einrichten** | Datei `.env` löschen — beim nächsten Start öffnet sich der Wizard wieder |
| **Beispiel-DB anlegen** | aus PowerShell: `.\init-db.ps1` |

## Tabellen

**Quelle** (muss vorhanden sein):

```sql
CREATE TABLE deelnemers_geaggregeerd (
  Deelnemersnummer TEXT PRIMARY KEY,
  aantal_rijen     INTEGER,
  tekst            TEXT          -- enthält den Pathologie-Bericht
);
```

> Heißt die Textspalte anders, in `.env` `TEXT_COLUMN` setzen.

**Ziel** (wird automatisch angelegt):

```sql
CREATE TABLE classificatie_resultaten (
  Deelnemersnummer    TEXT PRIMARY KEY,
  procedure           TEXT,
  sample_type         TEXT,
  who_kategorie       TEXT,
  who_kategorienummer INTEGER,
  confidence          INTEGER,
  verwerkt_op         TEXT
);
```

Bereits klassifizierte `Deelnemersnummer` werden übersprungen — abgebrochene
Läufe einfach erneut starten.

## Sicherheit

- Tabellen-/Spaltennamen aus `.env` werden gegen `^[A-Za-z_][A-Za-z0-9_]*$`
  validiert (kein SQL-Injection-Risiko über die Konfiguration).
- API-Key-Eingabe maskiert über den Windows-Anmeldedialog.
- Key wird vor dem Speichern gegen die OpenAI-API getestet.
- Die SQLite-DLL kommt von `nuget.org` (offizielles Paket
  `System.Data.SQLite.Core`).
- `.env` ist in `.gitignore` — landet nicht im Repo.

## Files

| Datei | Zweck |
|---|---|
| `start.bat` | Doppelklick-Starter |
| `categorize.ps1` | Hauptskript inkl. Erst-Setup-Wizard |
| `init-db.ps1` | erzeugt eine Beispiel-DB mit dem Beispielbericht |
| `.env.example` | Vorlage (wird vom Wizard ohnehin automatisch erzeugt) |
| `INSTALL.md` | ausführliche Anleitung mit Screenshots-Beschreibung |
