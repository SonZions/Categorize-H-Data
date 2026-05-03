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

In der PowerShell **im Projektordner**:

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

Wenn alles geklappt hat, beginnt die Eingabezeile mit `(.venv)`.

---

## 4. API-Key und Konfiguration einrichten

1. Datei `.env.example` kopieren und in `.env` umbenennen.
2. `.env` mit dem Editor öffnen und mindestens den OpenAI-Key eintragen:
   ```
   OPENAI_API_KEY=sk-...
   ```
3. Bei Bedarf weitere Werte anpassen:
   - `DB_PATH` – Pfad zur SQLite-Datei
   - `TABLE_NAME`, `ID_COLUMN`, `TEXT_COLUMN`, `CATEGORY_COLUMN` –
     Tabelle und Spalten in der Datenbank
   - `CATEGORIES` – komma-getrennte Liste erlaubter Kategorien
     (leer lassen, damit das Modell selbst Kategorien wählt)
   - `BATCH_SIZE` – wie viele Texte pro API-Aufruf gebündelt werden (Standard 10)
   - `OPENAI_MODEL` – Standard `gpt-4o-mini` (günstig und für
     Klassifikation gut geeignet)

---

## 5. (Optional) Beispiel-Datenbank erzeugen

Wenn noch keine Datenbank vorhanden ist, lässt sich eine Test-DB anlegen:

```powershell
python init_db.py
```

Damit entsteht `data.db` mit 10 Beispiel-Texten ohne Kategorie.

---

## 6. Kategorisierung starten

### Bequem per Doppelklick

Im Datei-Explorer einfach **`start.bat`** doppelklicken. Beim ersten
Aufruf legt das Skript automatisch die virtuelle Umgebung an und
installiert die Pakete (Schritt 3 entfällt dann). Anschließend wird
die Kategorisierung gestartet und das Fenster bleibt am Ende offen.

> Voraussetzung: `.env` ist angelegt und enthält den OpenAI-Key
> (siehe Punkt 4).

### Oder über die PowerShell

```powershell
python categorize.py
```

Zuerst empfiehlt sich ein Trockenlauf, der nichts in die DB schreibt:

```powershell
python categorize.py --dry-run --limit 20
```

Beim normalen Lauf werden alle Datensätze, deren Kategorie noch leer ist,
in Batches an die API geschickt und das Ergebnis sofort in die Datenbank
geschrieben. Bei ca. 500 Datensätzen und `BATCH_SIZE=10` sind das ungefähr
**50 API-Aufrufe**.

Das Skript ist **wiederholbar**: bereits kategorisierte Zeilen werden
übersprungen, abgebrochene Läufe können einfach erneut gestartet werden.

---

## 7. Ergebnisse prüfen

Mit einem grafischen SQLite-Tool wie **DB Browser for SQLite**
(https://sqlitebrowser.org – portable Version verfügbar, kein Admin nötig)
oder über die Kommandozeile:

```powershell
python -c "import sqlite3; [print(r) for r in sqlite3.connect('data.db').execute('SELECT id, kategorie, substr(text,1,40) FROM texte LIMIT 20')]"
```

---

## Häufige Probleme

| Problem | Lösung |
|---|---|
| `python` wird nicht gefunden | PowerShell schließen und neu öffnen, oder Punkt 1 wiederholen |
| `OPENAI_API_KEY ist nicht gesetzt` | Schritt 4 prüfen, `.env` muss im Projektordner liegen |
| `Activate.ps1 cannot be loaded` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` ausführen |
| `RateLimitError` von OpenAI | Skript erneut starten – bereits kategorisierte Zeilen bleiben erhalten |
| Falsche Kategorien | `CATEGORIES` in `.env` einschränken oder anpassen |

---

## Kosten (Richtwert)

Mit `gpt-4o-mini` und kurzen Texten kosten 500 Datensätze typischerweise
**unter 0,10 USD**. Genaue Abrechnung im OpenAI-Dashboard unter „Usage".
