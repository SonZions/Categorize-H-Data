# Installation und Bedienung (Windows ohne Adminrechte)

Diese Anleitung beschreibt Schritt für Schritt, wie das Tool auf einem
Windows-Rechner **ohne Administratorrechte** eingerichtet wird. Es werden
keine systemweiten Installationen benötigt – alles läuft im Benutzerprofil.

---

## 1. Python installieren

Es gibt zwei Wege, beide funktionieren ohne Adminrechte:

### Variante A (empfohlen): Microsoft Store

1. Im Startmenü „Microsoft Store" öffnen.
2. Nach **„Python 3.12"** suchen und auf *Installieren* klicken.
3. Nach der Installation eine neue **PowerShell** öffnen und prüfen:
   ```powershell
   python --version
   ```
   Es muss z. B. `Python 3.12.x` erscheinen.

### Variante B: Installer von python.org

1. https://www.python.org/downloads/windows/ öffnen und den aktuellen
   Installer für Python 3.12 (64-bit) herunterladen.
2. Installer starten und **wichtig**:
   - Häkchen bei **„Add python.exe to PATH"** setzen.
   - Auf **„Install Now"** klicken (Standard ist „Nur für mich" – kein Admin nötig).
3. Neue PowerShell öffnen und prüfen: `python --version`.

---

## 2. Projekt herunterladen

Im Datei-Explorer einen Ordner anlegen, z. B. `C:\Users\<Benutzer>\Categorize-H-Data`,
und das Projekt dort hinein entpacken (ZIP von GitHub) **oder** per Git klonen:

```powershell
cd $HOME
git clone https://github.com/SonZions/categorize-h-data.git Categorize-H-Data
cd Categorize-H-Data
```

---

## 3. Virtuelle Umgebung anlegen und Pakete installieren

Beim Doppelklick auf `start.bat` passiert das automatisch. Wer es manuell
machen will, in der PowerShell **im Projektordner**:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

> **Hinweis**: Falls `Activate.ps1` blockiert wird, einmalig in der
> aktuellen PowerShell-Sitzung erlauben (kein Admin nötig):
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```

---

## 4. API-Key und Konfiguration einrichten

1. `.env.example` kopieren und in `.env` umbenennen.
2. `.env` mit dem Editor öffnen und mindestens den OpenAI-Key eintragen:
   ```
   OPENAI_API_KEY=sk-...
   ```
3. Bei Bedarf weitere Werte anpassen:
   - `DB_PATH` – Pfad zur SQLite-Datei (z. B. `C:\Daten\verslagen.db`)
   - `SOURCE_TABLE` – Brontabelle (Standard `deelnemers_geaggregeerd`)
   - `ID_COLUMN` – Identifierspalte (Standard `Deelnemersnummer`)
   - `TEXT_COLUMN` – **Spalte mit dem Pathologie-Verslag**
     (Standard `tekst` – muss ggf. an den realen Spaltennamen angepasst werden!)
   - `RESULT_TABLE` – Zieltabelle für Ergebnisse (Standard
     `classificatie_resultaten`, wird automatisch angelegt)
   - `OPENAI_MODEL` – Standard `gpt-4o-mini` (günstig). Bei schwierigen Fällen
     `gpt-4o` ausprobieren.
   - `BATCH_SIZE` – Verslagen pro API-Aufruf (Standard 5; höher = günstiger,
     aber Risiko für Token-Limits bei langen Texten).

---

## 5. Datenmodell

### Quelle (muss vorhanden sein)

```sql
CREATE TABLE deelnemers_geaggregeerd (
  Deelnemersnummer TEXT PRIMARY KEY,
  aantal_rijen     INTEGER,
  tekst            TEXT          -- Spalte mit dem Pathologie-Verslag
);
```

> Heißt die Textspalte anders, in `.env` `TEXT_COLUMN` entsprechend setzen.

### Ziel (wird automatisch angelegt)

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

Bereits klassifizierte `Deelnemersnummer` werden bei Folgeläufen
übersprungen (Resume-fähig).

---

## 6. (Optional) Beispiel-Datenbank erzeugen

Wenn keine echte DB vorhanden ist, kann eine Test-DB angelegt werden:

```powershell
python init_db.py
```

Damit entsteht `data.db` mit einem Beispiel-Pathologiebericht.

---

## 7. Klassifikation starten

### Bequem per Doppelklick

Im Datei-Explorer **`start.bat`** doppelklicken. Beim ersten Aufruf legt das
Skript automatisch die virtuelle Umgebung an und installiert die Pakete.
Anschließend wird die Klassifikation gestartet und das Fenster bleibt am
Ende offen.

> Voraussetzung: `.env` ist angelegt und enthält den OpenAI-Key.

### Oder über die PowerShell

```powershell
python categorize.py --dry-run --limit 1   # Testlauf, schreibt nichts
python categorize.py                       # Echtlauf
```

Bei ca. 500 Datensätzen und `BATCH_SIZE=5` sind das ungefähr
**100 API-Aufrufe**. Das Skript ist **wiederholbar**: bereits klassifizierte
Datensätze (vorhanden in `classificatie_resultaten`) werden übersprungen.

---

## 8. Ergebnisse prüfen

Mit einem grafischen SQLite-Tool wie **DB Browser for SQLite**
(https://sqlitebrowser.org – portable Version verfügbar, kein Admin nötig)
oder über die Kommandozeile:

```powershell
python -c "import sqlite3; [print(r) for r in sqlite3.connect('data.db').execute('SELECT Deelnemersnummer, procedure, sample_type, who_kategorienummer, confidence FROM classificatie_resultaten LIMIT 20')]"
```

---

## Häufige Probleme

| Problem | Lösung |
|---|---|
| `python` wird nicht gefunden | PowerShell schließen und neu öffnen, oder Punkt 1 wiederholen |
| `OPENAI_API_KEY niet gezet` | Schritt 4 prüfen, `.env` muss im Projektordner liegen |
| `database niet gevonden` | `DB_PATH` in `.env` prüfen oder `python init_db.py` ausführen |
| `Activate.ps1 cannot be loaded` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` ausführen |
| `RateLimitError` von OpenAI | Skript erneut starten – schon klassifizierte Zeilen bleiben erhalten |
| Niedrige Confidence | Modell auf `gpt-4o` umstellen (`OPENAI_MODEL` in `.env`) |
| `no such column: tekst` | `TEXT_COLUMN` in `.env` an die echte Spalte anpassen |

---

## Kosten (Richtwert)

Mit `gpt-4o-mini` und langen Pathologieberichten (jeweils ~1–2 KB) liegen
500 Datensätze typischerweise im **niedrigen einstelligen USD-Bereich**.
Genaue Abrechnung im OpenAI-Dashboard unter „Usage". Bei `gpt-4o` rund
**Faktor 15** teurer.
