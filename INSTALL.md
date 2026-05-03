# Anleitung für die Schwägerin (Windows, ohne Adminrechte)

Diese Anleitung ist bewusst einfach gehalten. Du brauchst keine
Programmiererfahrung. Es muss **nichts installiert werden** — Windows bringt
alles Nötige (PowerShell) bereits mit.

Was du dafür schon hast:
- Den **OpenAI API-Key** (beginnt mit `sk-...`)
- Den **Pfad zur SQLite-Datenbank** mit den Berichten

---

## Schritt 1 — Projekt herunterladen

Auf der Projektseite auf GitHub oben rechts auf den grünen **Code**-Button
klicken → *Download ZIP*. Die ZIP-Datei in einem Ordner deiner Wahl entpacken,
zum Beispiel `C:\Users\<DeinName>\Documents\Categorize-H-Data\`.

---

## Schritt 2 — Doppelklick auf `start.bat`

Im Projektordner findest du eine Datei `start.bat`. **Doppelklick** genügt.

Es öffnet sich ein schwarzes Konsolenfenster. Beim ersten Start passiert
Folgendes:

### 2a. Einmalige Begrüßung

Das Skript begrüßt dich und erklärt, dass es zwei Angaben braucht.

### 2b. API-Key abfragen

Es öffnet sich ein **Windows-Anmeldedialog** mit dem Text *„Bitte den OpenAI
API-Key als Passwort einfügen"*. Im Feld *Passwort*:

- Den API-Key per **Strg + V** einfügen (Rechtsklick → Einfügen geht auch).
- Das Feld zeigt nur Punkte — das ist Absicht, damit niemand mitliest.
- Auf **OK** klicken.

Das Skript prüft den Key sofort bei OpenAI. Bei Tippfehler kommt eine klare
Meldung und der Dialog öffnet sich erneut.

### 2c. Datenbank auswählen

Anschließend öffnet sich ein **Datei-Dialog**. Suche dort die SQLite-Datei
mit den Pathologie-Berichten (`.db`, `.sqlite` oder `.sqlite3`) und klicke
auf *Öffnen*.

### 2d. Übersicht und Bestätigung

Das Skript zeigt eine Zusammenfassung:

```
============================================================
  Zusammenfassung
============================================================
  Datenbank: C:\Pfad\zur\datei.db
  Modell:    gpt-4o-mini
  Offene Datensätze: 487
  Batchgrösse:       5  (also ca. 98 API-Aufrufe)

Mit der Klassifikation beginnen? [J/n]
```

- **J** + Enter → es geht los.
- **N** + Enter → nichts wird verändert, du kannst das Fenster schließen.

### 2e. Klassifikation läuft

Pro Batch siehst du, was klassifiziert wurde:

```
Batch 12/98 (5 Berichte) ...
  DLN-0123: proc=ERCP, sample=brush, WHO=7, conf=85%
  DLN-0124: proc=EUS,  sample=biopt, WHO=2, conf=90%
  ...
```

### 2f. Fertig

Am Ende:

```
============================================================
  Fertig
============================================================
Klassifiziert:    487
Ergebnistabelle: classificatie_resultaten in C:\Pfad\zur\datei.db
```

Drücke eine beliebige Taste, um das Fenster zu schließen.

---

## Wenn etwas nicht klappt

Das Skript zeigt Fehlermeldungen in einem roten Block:

```
============================================================
  FEHLER
============================================================
<Klartext, was schiefgegangen ist>

Tipp: Bei Fragen einen Screenshot dieses Fensters machen.
```

Mach in dem Fall einen Screenshot und schick ihn dem Helfer (mir/Schwager/…).

### Häufige Meldungen

| Meldung | Bedeutung & Lösung |
|---|---|
| **OpenAI hat den Key nicht akzeptiert** | Tippfehler beim Einfügen — erneut versuchen, ggf. neuen Key bei OpenAI generieren. |
| **Datenbank nicht gefunden** | Die DB-Datei wurde verschoben oder umbenannt. `.env` löschen, dann öffnet sich beim nächsten Start wieder der Auswahldialog. |
| **Es gibt aktuell keine offenen Datensätze** | Alles bereits klassifiziert. Ergebnisse stehen in der Tabelle `classificatie_resultaten`. |
| **PowerShell wird nicht gefunden** | Sehr selten — `start.bat` startet PowerShell automatisch. Falls das tatsächlich fehlt: Windows-Update installieren. |

---

## Was tun, wenn ich etwas ändern will?

Im Projektordner liegt eine Datei `.env`. Sie enthält die Einstellungen.
Mit Notepad öffnen und Wert anpassen — fertig.

| Eintrag | Bedeutung |
|---|---|
| `OPENAI_API_KEY` | Dein API-Key |
| `DB_PATH` | Pfad zur Datenbank |
| `SOURCE_TABLE` | Quelltabelle (Standard `deelnemers_geaggregeerd`) |
| `TEXT_COLUMN` | Spalte mit dem Bericht (Standard `tekst`) |
| `OPENAI_MODEL` | `gpt-4o-mini` (günstig) oder `gpt-4o` (genauer, ~15× teurer) |
| `BATCH_SIZE` | Berichte pro API-Aufruf (Standard `5`) |

Komplett neu starten? `.env` löschen — beim nächsten Doppelklick auf
`start.bat` öffnet sich der Einrichtungs-Wizard erneut.

---

## Ergebnisse anschauen

Lade dir bei Bedarf den **DB Browser for SQLite** herunter
(https://sqlitebrowser.org → *Standard installer* oder die portable Version).
Damit kannst du die Tabelle `classificatie_resultaten` öffnen und sortieren.

---

## Kosten (Richtwert)

Mit `gpt-4o-mini` und langen Pathologieberichten liegen 500 Datensätze
typischerweise im **niedrigen einstelligen USD-Bereich**. Genaue Abrechnung
im OpenAI-Dashboard unter „Usage".
