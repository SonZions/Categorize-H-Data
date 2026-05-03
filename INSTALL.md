# Installation und Bedienung (Windows ohne Adminrechte)

Dieses Tool ist **pure PowerShell** — es muss nichts installiert werden.
Windows 10/11 bringen PowerShell 5.1 von Haus aus mit. Die einzige externe
Abhängigkeit (eine SQLite-DLL, ~1.5 MB) wird beim ersten Start automatisch
in den Projektordner heruntergeladen. Nichts auf Systemebene wird verändert.

---

## 1. Projekt herunterladen

Im Datei-Explorer einen Ordner anlegen, z. B.
`C:\Users\<Benutzer>\Categorize-H-Data`, und das Projekt dort hinein
entpacken (ZIP von GitHub) **oder** per Git klonen:

```powershell
cd $HOME
git clone https://github.com/SonZions/Categorize-H-Data.git
cd Categorize-H-Data
```

> Wer Git nicht hat: ZIP herunterladen und entpacken reicht.

---

## 2. API-Key und Konfiguration einrichten

1. `.env.example` kopieren und in `.env` umbenennen.
2. `.env` mit dem Editor öffnen und mindestens den OpenAI-Key eintragen:
   ```
   OPENAI_API_KEY=sk-...
   ```
3. Bei Bedarf weitere Werte anpassen:
   - `DB_PATH` – Pfad zur SQLite-Datei (z. B. `C:\Daten\verslagen.db`)
   - `SOURCE_TABLE` – Brontabelle (Standard `deelnemers_geaggregeerd`)
   - `ID_COLUMN` – Identifier-Spalte (Standard `Deelnemersnummer`)
   - `TEXT_COLUMN` – **Spalte mit dem Pathologie-Verslag** (Standard `tekst`
     – muss ggf. an den realen Spaltennamen angepasst werden!)
   - `RESULT_TABLE` – Zieltabelle für Ergebnisse (Standard
     `classificatie_resultaten`, wird automatisch angelegt)
   - `OPENAI_MODEL` – Standard `gpt-4o-mini` (günstig). Bei schwierigen
     Fällen `gpt-4o`.
   - `BATCH_SIZE` – Verslagen pro API-Aufruf (Standard 5).

---

## 3. Datenmodell

### Quelle (muss vorhanden sein)

```sql
CREATE TABLE deelnemers_geaggregeerd (
  Deelnemersnummer TEXT PRIMARY KEY,
  aantal_rijen     INTEGER,
  tekst            TEXT          -- Spalte mit dem Pathologie-Verslag
);
```

> Heißt die Textspalte anders, in `.env` `TEXT_COLUMN` entsprechend setzen.

### Ziel (wird beim ersten Lauf automatisch angelegt)

```sql
CREATE TABLE classificatie_resultaten (
  Deelnemersnummer    TEXT PRIMARY KEY,
  procedure           TEXT,    -- ERCP / EUS / onbekend
  sample_type         TEXT,    -- biopt / brush / gal_aspirate / onbekend
  who_kategorie       TEXT,    -- Name der WHO-Kategorie
  who_kategorienummer INTEGER, -- 1–7 (Arabische Ziffer)
  confidence          INTEGER, -- 0–100 (%)
  verwerkt_op         TEXT     -- ISO-Zeitstempel
);
```

---

## 4. (Optional) Beispiel-Datenbank erzeugen

Wenn keine echte DB vorhanden ist, kann eine Test-DB angelegt werden:

```powershell
.\init-db.ps1
```

Damit entsteht `data.db` mit einem Beispiel-Pathologiebericht.

---

## 5. Klassifikation starten

### Bequem per Doppelklick

Im Datei-Explorer **`start.bat`** doppelklicken. Was passiert:

1. PowerShell wird mit `-ExecutionPolicy Bypass` gestartet (kein Admin
   nötig, gilt nur für diesen Lauf).
2. Beim allerersten Mal wird die SQLite-DLL nach `lib/` heruntergeladen
   (~1.5 MB von nuget.org).
3. `categorize.ps1` läuft, klassifiziert alle offenen Datensätze und
   schreibt das Ergebnis in `classificatie_resultaten`.
4. Das Fenster bleibt am Ende offen (`pause`), egal ob Erfolg oder Fehler.

> Voraussetzung: `.env` ist angelegt und enthält den OpenAI-Key.

### Oder direkt aus PowerShell

```powershell
.\categorize.ps1 -DryRun -Limit 1     # Testlauf, schreibt nichts
.\categorize.ps1                      # Echtlauf
.\categorize.ps1 -Limit 50            # nur die ersten 50 verarbeiten
```

> Falls PowerShell `.ps1`-Skripte blockiert, einmal pro Sitzung:
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```

Bei ca. 500 Datensätzen und `BATCH_SIZE=5` sind das ungefähr **100
API-Aufrufe**. Das Skript ist **wiederholbar**: bereits klassifizierte
Datensätze (vorhanden in `classificatie_resultaten`) werden übersprungen.

---

## 6. Ergebnisse prüfen

Mit einem grafischen SQLite-Tool wie **DB Browser for SQLite**
(https://sqlitebrowser.org – portable Variante verfügbar, kein Admin nötig)
oder über PowerShell:

```powershell
Add-Type -Path .\lib\System.Data.SQLite.dll
$c = New-Object System.Data.SQLite.SQLiteConnection("Data Source=data.db;Version=3;")
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT Deelnemersnummer, procedure, sample_type, who_kategorienummer, confidence FROM classificatie_resultaten LIMIT 20"
$r = $cmd.ExecuteReader()
while ($r.Read()) { "{0} | {1} | {2} | WHO {3} | {4}%" -f $r[0],$r[1],$r[2],$r[3],$r[4] }
$c.Close()
```

---

## Häufige Probleme

| Problem | Lösung |
|---|---|
| `PowerShell blockiert das Skript` | `start.bat` benutzen, oder `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `OPENAI_API_KEY ontbreekt` | `.env` muss im Projektordner liegen und den Key enthalten |
| `Database niet gevonden` | `DB_PATH` in `.env` prüfen oder `.\init-db.ps1` ausführen |
| Download der SQLite-DLL schlägt fehl | Internetverbindung prüfen, Firewall/Proxy für `nuget.org` freigeben |
| `no such column: tekst` | `TEXT_COLUMN` in `.env` an die echte Spalte anpassen |
| Niedrige Confidence | `OPENAI_MODEL` in `.env` auf `gpt-4o` umstellen |

---

## Kosten (Richtwert)

Mit `gpt-4o-mini` und langen Pathologieberichten (~1–2 KB pro Stück) liegen
500 Datensätze typischerweise im **niedrigen einstelligen USD-Bereich**.
Genaue Abrechnung im OpenAI-Dashboard unter „Usage". Bei `gpt-4o` rund
**Faktor 15** teurer.
