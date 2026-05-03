[CmdletBinding()]
param(
    [int]$Limit,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot

# ----- helpers ----------------------------------------------------------------

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Assert-SafeIdentifier {
    param([string]$Name, [string]$What)
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Ungültiger $What '$Name'. Erlaubt sind Buchstaben, Ziffern und Unterstrich."
    }
}

function Load-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $name = $Matches[1]
            $value = $Matches[2].Trim('"').Trim("'")
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

function Save-DotEnv {
    param([string]$Path, [string]$ApiKey, [string]$DbPath)
    $content = @"
# Automatisch erstellt durch Erst-Einrichtung am $(Get-Date -Format 'yyyy-MM-dd HH:mm').
# Du kannst diese Werte bearbeiten — eine Zeile pro Einstellung.
OPENAI_API_KEY=$ApiKey
DB_PATH=$DbPath
SOURCE_TABLE=deelnemers_geaggregeerd
ID_COLUMN=Deelnemersnummer
TEXT_COLUMN=tekst
RESULT_TABLE=classificatie_resultaten
OPENAI_MODEL=gpt-4o-mini
BATCH_SIZE=5
"@
    Set-Content -Path $Path -Value $content -Encoding UTF8
}

function Test-OpenAIKey {
    param([string]$Key)
    try {
        $null = Invoke-RestMethod -Uri 'https://api.openai.com/v1/models' `
            -Method Get -Headers @{ Authorization = "Bearer $Key" } -TimeoutSec 15
        return $true
    } catch {
        return $false
    }
}

function Ensure-Sqlite {
    param([string]$LibDir)
    $managed = Join-Path $LibDir 'System.Data.SQLite.dll'
    $native  = Join-Path $LibDir 'SQLite.Interop.dll'
    if ((Test-Path $managed) -and (Test-Path $native)) { return $managed }

    Write-Host "Einmaliger Download der SQLite-Bibliothek (~1.5 MB) ..."
    New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
    $tmp = Join-Path $env:TEMP ("sqlitecore_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $nupkg = Join-Path $tmp 'pkg.zip'
        $url = 'https://www.nuget.org/api/v2/package/System.Data.SQLite.Core/1.0.119'
        Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extract = Join-Path $tmp 'pkg'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extract)
        $arch = if ([Environment]::Is64BitOperatingSystem) { 'win-x64' } else { 'win-x86' }
        Copy-Item (Join-Path $extract 'lib\net46\System.Data.SQLite.dll') $managed -Force
        Copy-Item (Join-Path $extract "runtimes\$arch\native\netstandard2.0\SQLite.Interop.dll") $native -Force
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Write-Host "OK — SQLite einsatzbereit."
    return $managed
}

function Show-WelcomeWizard {
    param([string]$EnvPath)

    Add-Type -AssemblyName System.Windows.Forms

    Write-Section 'Erste Einrichtung'
    Write-Host "Hallo! Beim ersten Start brauche ich zwei Angaben:"
    Write-Host "  1) Deinen OpenAI API-Key"
    Write-Host "  2) Den Pfad zur SQLite-Datenbank"
    Write-Host ""
    Write-Host "Beides wird in einer Datei .env im Projektordner gespeichert."
    Write-Host "Du kannst sie spaeter jederzeit aendern."
    Write-Host ""

    # --- 1) API key ---
    $apiKey = $null
    while (-not $apiKey) {
        Write-Host "Schritt 1/2: API-Key eingeben (es oeffnet sich ein Dialog)." -ForegroundColor Yellow
        $cred = Get-Credential -UserName 'openai' `
            -Message "Bitte den OpenAI API-Key als Passwort einfuegen (beginnt mit 'sk-')."
        if (-not $cred) { throw "Abbruch — kein API-Key eingegeben." }
        $candidate = $cred.GetNetworkCredential().Password

        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Write-Warning "Leeres Feld. Bitte erneut versuchen."
            continue
        }
        if (-not $candidate.StartsWith('sk-')) {
            Write-Warning "Der Key beginnt nicht mit 'sk-' — vermutlich ein Tippfehler."
            $again = Read-Host "Trotzdem testen? [j/N]"
            if ($again -notmatch '^[jJ]$') { continue }
        }

        Write-Host "Teste den Key bei OpenAI ..." -NoNewline
        if (Test-OpenAIKey -Key $candidate) {
            Write-Host " OK." -ForegroundColor Green
            $apiKey = $candidate
        } else {
            Write-Host " fehlgeschlagen." -ForegroundColor Red
            Write-Warning "OpenAI hat den Key nicht akzeptiert. Bitte erneut eingeben."
        }
    }

    # --- 2) DB file picker ---
    Write-Host ""
    Write-Host "Schritt 2/2: Datenbank-Datei auswaehlen (Datei-Dialog oeffnet sich)." -ForegroundColor Yellow
    Write-Host "Tipp: Du kannst den vollstaendigen Pfad auch oben in den Dialog einfuegen."
    Read-Host "Druecke Enter, um den Dialog zu oeffnen"

    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'SQLite-Datenbank mit den Pathologie-Berichten waehlen'
    $dlg.Filter = 'SQLite-Datenbanken (*.db;*.sqlite;*.sqlite3)|*.db;*.sqlite;*.sqlite3|Alle Dateien (*.*)|*.*'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    $dlg.CheckFileExists = $true
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw "Abbruch — keine Datenbank ausgewaehlt."
    }
    $dbPath = $dlg.FileName
    Write-Host "Gewaehlt: $dbPath" -ForegroundColor Green

    Save-DotEnv -Path $EnvPath -ApiKey $apiKey -DbPath $dbPath
    Write-Host ""
    Write-Host "Einstellungen gespeichert in: $EnvPath" -ForegroundColor Green
    Write-Host ""
}

function Confirm-Run {
    param([int]$Count, [string]$Model, [string]$Db, [int]$Batch)
    Write-Section 'Zusammenfassung'
    Write-Host "  Datenbank: $Db"
    Write-Host "  Modell:    $Model"
    Write-Host "  Offene Datensaetze: $Count"
    Write-Host "  Batchgroesse:       $Batch  (also ca. $([Math]::Ceiling($Count/[double]$Batch)) API-Aufrufe)"
    if ($DryRun) {
        Write-Host "  Modus:     TROCKENLAUF — es wird NICHTS gespeichert" -ForegroundColor Yellow
    }
    Write-Host ""
    if ($Yes) { return $true }
    $answer = Read-Host "Mit der Klassifikation beginnen? [J/n]"
    return ($answer -eq '' -or $answer -match '^[jJ]')
}

# ----- main -------------------------------------------------------------------

try {
    Write-Section 'Categorize-H-Data'

    $envPath = Join-Path $Root '.env'
    if (-not (Test-Path $envPath)) {
        Show-WelcomeWizard -EnvPath $envPath
    }
    Load-DotEnv $envPath

    if (-not $env:OPENAI_API_KEY) { throw "OPENAI_API_KEY fehlt in .env." }
    $DbPath      = if ($env:DB_PATH)      { $env:DB_PATH }      else { Join-Path $Root 'data.db' }
    $SourceTable = if ($env:SOURCE_TABLE) { $env:SOURCE_TABLE } else { 'deelnemers_geaggregeerd' }
    $IdCol       = if ($env:ID_COLUMN)    { $env:ID_COLUMN }    else { 'Deelnemersnummer' }
    $TextCol     = if ($env:TEXT_COLUMN)  { $env:TEXT_COLUMN }  else { 'tekst' }
    $ResultTable = if ($env:RESULT_TABLE) { $env:RESULT_TABLE } else { 'classificatie_resultaten' }
    $Model       = if ($env:OPENAI_MODEL) { $env:OPENAI_MODEL } else { 'gpt-4o-mini' }
    $BatchSize   = if ($env:BATCH_SIZE)   { [int]$env:BATCH_SIZE } else { 5 }

    Assert-SafeIdentifier $SourceTable 'SOURCE_TABLE'
    Assert-SafeIdentifier $ResultTable 'RESULT_TABLE'
    Assert-SafeIdentifier $IdCol       'ID_COLUMN'
    Assert-SafeIdentifier $TextCol     'TEXT_COLUMN'

    if (-not (Test-Path $DbPath)) {
        throw "Datenbank nicht gefunden: $DbPath`nBitte den Pfad in .env korrigieren oder die Datei dorthin kopieren."
    }

    $sqliteDll = Ensure-Sqlite (Join-Path $Root 'lib')
    Add-Type -Path $sqliteDll

    # --- WHO categories --------------------------------------------------------
    $WhoCategories = [ordered]@{
        1 = 'Insufficient / Inadequate / Non-diagnostic'
        2 = 'Benign / Negative for malignancy'
        3 = 'Atypical'
        4 = 'Pancreaticobiliary Neoplasm, Low Risk / Low Grade (PaN-Low)'
        5 = 'Pancreaticobiliary Neoplasm, High Risk / High Grade (PaN-High)'
        6 = 'Suspicious for malignancy'
        7 = 'Malignant'
    }
    $WhoDescriptions = [ordered]@{
        1 = 'Onvoldoende of niet-diagnostisch materiaal voor een betrouwbare beoordeling.'
        2 = 'Goedaardig; geen aanwijzingen voor maligniteit.'
        3 = 'Cellulaire afwijkingen die niet voldoen aan criteria voor neoplasie of maligniteit.'
        4 = 'Pancreaticobiliaire neoplasie met laag risico of lage gradering.'
        5 = 'Pancreaticobiliaire neoplasie met hoog risico of hoge gradering.'
        6 = 'Verdacht voor maligniteit; criteria voor maligniteit niet volledig vervuld.'
        7 = 'Maligne; cytologisch of histologisch bewijs van maligniteit.'
    }
    $catBlock = ($WhoCategories.Keys | ForEach-Object {
        "  $_. $($WhoCategories[$_]) -- $($WhoDescriptions[$_])"
    }) -join "`n"
    $catNames = @($WhoCategories.Values)

    $SystemPrompt = @"
Je bent een ervaren patholoog-assistent. Je analyseert Nederlandstalige pathologie-verslagen in het kader van mogelijke maligne distale galwegobstructie en classificeert elk verslag op drie aspecten.

Voor elk verslag bepaal je:

1. PROCEDURE -- Screen de gehele tekst: gaat het om een ERCP (Endoscopic Retrograde Cholangiopancreatography) of EUS (Endoscopic Ultrasound)? Antwoord met exact "ERCP", "EUS" of "onbekend".

2. SAMPLE_TYPE -- Screen de gehele tekst op het soort afgenomen materiaal:
   - "biopt"        (incl. biopsie, naaldbiopt, core needle biopsy)
   - "brush"        (incl. borstel, borstel-cytologie, cytologische borstel)
   - "gal_aspirate" (incl. galaspiraat, gal-aspiraat, bile aspirate, galvocht)
   - "onbekend"     wanneer geen van bovenstaande eenduidig genoemd is.

3. WHO-CATEGORIE -- Classificeer de CONCLUSIE volgens "The World Health Organization Reporting System for Pancreaticobiliary Cytopathology" (meest recente versie, 2022). Kies precies EEN categorie:
$catBlock

   Geef het categorienummer als Arabisch cijfer 1-7 (kategorienummer) en de exacte categorienaam zoals hierboven (kategorie).

4. CONFIDENCE -- Geef in procenten (geheel getal 0-100) aan hoe zeker je bent over de WHO-classificatie.

Antwoord UITSLUITEND met geldig JSON volgens het opgegeven schema. Geef voor elke aangevraagde id precies een resultaat-object terug.
"@

    # --- DB connection + result table -----------------------------------------
    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DbPath;Version=3;")
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS "$ResultTable" (
  "$IdCol"             TEXT PRIMARY KEY,
  procedure            TEXT,
  sample_type          TEXT,
  who_kategorie        TEXT,
  who_kategorienummer  INTEGER,
  confidence           INTEGER,
  verwerkt_op          TEXT
)
"@
        [void]$cmd.ExecuteNonQuery()

        $sel = $conn.CreateCommand()
        $sel.CommandText = @"
SELECT s."$IdCol", s."$TextCol"
FROM "$SourceTable" s
LEFT JOIN "$ResultTable" r ON r."$IdCol" = s."$IdCol"
WHERE r."$IdCol" IS NULL AND s."$TextCol" IS NOT NULL AND s."$TextCol" <> ''
"@
        if ($Limit) { $sel.CommandText += " LIMIT $Limit" }

        $rows = New-Object System.Collections.Generic.List[object]
        $reader = $sel.ExecuteReader()
        while ($reader.Read()) {
            $rows.Add([pscustomobject]@{ Id = [string]$reader[0]; Text = [string]$reader[1] })
        }
        $reader.Close()

        if ($rows.Count -eq 0) {
            Write-Host "Es gibt aktuell keine offenen Datensätze." -ForegroundColor Green
            Write-Host "Bereits klassifiziert in: $ResultTable"
            return
        }

        if (-not (Confirm-Run -Count $rows.Count -Model $Model -Db $DbPath -Batch $BatchSize)) {
            Write-Host "Abgebrochen — nichts wurde geändert." -ForegroundColor Yellow
            return
        }

        Write-Section 'Klassifikation läuft'

        $headers = @{ Authorization = "Bearer $($env:OPENAI_API_KEY)" }
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $totalBatches = [Math]::Ceiling($rows.Count / [double]$BatchSize)
        $okCount = 0; $missCount = 0

        for ($i = 0; $i -lt $rows.Count; $i += $BatchSize) {
            $end = [Math]::Min($i + $BatchSize - 1, $rows.Count - 1)
            $batch = $rows[$i..$end]
            $batchNo = [int]($i / $BatchSize) + 1
            Write-Host "Batch $batchNo/$totalBatches ($($batch.Count) Berichte) ..."

            $userPayload = @{
                verslagen = @($batch | ForEach-Object { @{ id = $_.Id; tekst = $_.Text } })
            }
            $userJson = $userPayload | ConvertTo-Json -Depth 10 -Compress

            $body = @{
                model = $Model
                temperature = 0
                messages = @(
                    @{ role = 'system'; content = $SystemPrompt }
                    @{ role = 'user';   content = $userJson }
                )
                response_format = @{
                    type = 'json_schema'
                    json_schema = @{
                        name = 'pathologie_classificatie'
                        strict = $true
                        schema = @{
                            type = 'object'
                            additionalProperties = $false
                            required = @('results')
                            properties = @{
                                results = @{
                                    type = 'array'
                                    items = @{
                                        type = 'object'
                                        additionalProperties = $false
                                        required = @('id','procedure','sample_type','kategorie','kategorienummer','confidence')
                                        properties = @{
                                            id              = @{ type = 'string' }
                                            procedure       = @{ type = 'string'; enum = @('ERCP','EUS','onbekend') }
                                            sample_type     = @{ type = 'string'; enum = @('biopt','brush','gal_aspirate','onbekend') }
                                            kategorie       = @{ type = 'string'; enum = $catNames }
                                            kategorienummer = @{ type = 'integer'; minimum = 1; maximum = 7 }
                                            confidence      = @{ type = 'integer'; minimum = 0; maximum = 100 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } | ConvertTo-Json -Depth 30
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

            $delay = 2; $resp = $null
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    $resp = Invoke-RestMethod -Uri 'https://api.openai.com/v1/chat/completions' `
                        -Method Post -Headers $headers -ContentType 'application/json' `
                        -Body $bodyBytes
                    break
                } catch {
                    if ($attempt -eq 3) { throw }
                    Write-Warning "API-Fehler ($($_.Exception.Message)). Neuer Versuch in $delay Sek."
                    Start-Sleep -Seconds $delay
                    $delay *= 2
                }
            }

            $parsed = $resp.choices[0].message.content | ConvertFrom-Json
            $byId = @{}
            foreach ($r in $parsed.results) { $byId[[string]$r.id] = $r }

            foreach ($item in $batch) {
                $r = $byId[$item.Id]
                if (-not $r) {
                    Write-Warning "  Kein Ergebnis fuer $($item.Id)"
                    $missCount++
                    continue
                }
                $line = "  $($item.Id): proc=$($r.procedure), sample=$($r.sample_type), WHO=$($r.kategorienummer), conf=$($r.confidence)%"
                if ($DryRun) {
                    Write-Host "[DRY]$line"
                } else {
                    Write-Host $line
                    $upd = $conn.CreateCommand()
                    $upd.CommandText = "INSERT OR REPLACE INTO `"$ResultTable`" (`"$IdCol`", procedure, sample_type, who_kategorie, who_kategorienummer, confidence, verwerkt_op) VALUES (@id,@p,@s,@k,@n,@c,@t)"
                    [void]$upd.Parameters.AddWithValue('@id', $item.Id)
                    [void]$upd.Parameters.AddWithValue('@p',  [string]$r.procedure)
                    [void]$upd.Parameters.AddWithValue('@s',  [string]$r.sample_type)
                    [void]$upd.Parameters.AddWithValue('@k',  [string]$r.kategorie)
                    [void]$upd.Parameters.AddWithValue('@n',  [int]$r.kategorienummer)
                    [void]$upd.Parameters.AddWithValue('@c',  [int]$r.confidence)
                    [void]$upd.Parameters.AddWithValue('@t',  $now)
                    [void]$upd.ExecuteNonQuery()
                }
                $okCount++
            }
        }

        Write-Section 'Fertig'
        Write-Host "Klassifiziert:    $okCount" -ForegroundColor Green
        if ($missCount -gt 0) {
            Write-Host "Ohne Ergebnis:    $missCount" -ForegroundColor Yellow
        }
        if ($DryRun) {
            Write-Host "Hinweis: TROCKENLAUF — nichts gespeichert." -ForegroundColor Yellow
        } else {
            Write-Host "Ergebnistabelle: $ResultTable in $DbPath"
        }
    } finally {
        $conn.Close()
    }
}
catch {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "  FEHLER" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Tipp: Bei Fragen einen Screenshot dieses Fensters machen."
    exit 1
}
