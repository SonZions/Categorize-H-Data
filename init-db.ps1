[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot

function Load-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $name = $Matches[1]
            $value = $Matches[2].Trim('"').Trim("'")
            if (-not (Test-Path "Env:$name")) {
                Set-Item -Path "Env:$name" -Value $value
            }
        }
    }
}

function Ensure-Sqlite {
    param([string]$LibDir)
    $managed = Join-Path $LibDir 'System.Data.SQLite.dll'
    $native  = Join-Path $LibDir 'SQLite.Interop.dll'
    if ((Test-Path $managed) -and (Test-Path $native)) { return $managed }

    Write-Host "Eerste keer: SQLite-bibliotheek wordt gedownload (~1.5 MB)..."
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
    Write-Host "SQLite klaar in $LibDir"
    return $managed
}

Load-DotEnv (Join-Path $Root '.env')

$DbPath      = if ($env:DB_PATH)      { $env:DB_PATH }      else { Join-Path $Root 'data.db' }
$SourceTable = if ($env:SOURCE_TABLE) { $env:SOURCE_TABLE } else { 'deelnemers_geaggregeerd' }
$IdCol       = if ($env:ID_COLUMN)    { $env:ID_COLUMN }    else { 'Deelnemersnummer' }
$TextCol     = if ($env:TEXT_COLUMN)  { $env:TEXT_COLUMN }  else { 'tekst' }

$sqliteDll = Ensure-Sqlite (Join-Path $Root 'lib')
Add-Type -Path $sqliteDll

$VoorbeeldTekst = @'
Datum ontvangst: 21 juni
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
Biopten laesie buikwand: tumorpositief, waarbij sprake is van lokalisatie van een maligne B-cellymfoom. Reeds op biopten van elders in het lichaam (papil van Vater, morfologisch hetzelfde beeld) is voor verdere typering analyse ingezet; zie derhalve voor de verdere analyse van het lymfoom de uitslag onder RPA09-962881.
'@

$conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DbPath;Version=3;")
$conn.Open()
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "CREATE TABLE IF NOT EXISTS `"$SourceTable`" (`"$IdCol`" TEXT PRIMARY KEY, aantal_rijen INTEGER, `"$TextCol`" TEXT)"
    [void]$cmd.ExecuteNonQuery()

    $cmd.CommandText = "SELECT COUNT(*) FROM `"$SourceTable`""
    $count = [int]$cmd.ExecuteScalar()
    if ($count -gt 0) {
        Write-Host "Tabel $SourceTable bevat al data ($count rijen) - niets toegevoegd."
    } else {
        $ins = $conn.CreateCommand()
        $ins.CommandText = "INSERT INTO `"$SourceTable`" (`"$IdCol`", aantal_rijen, `"$TextCol`") VALUES (@id, @n, @t)"
        [void]$ins.Parameters.AddWithValue('@id', 'DLN-0001')
        [void]$ins.Parameters.AddWithValue('@n',  1)
        [void]$ins.Parameters.AddWithValue('@t',  $VoorbeeldTekst)
        [void]$ins.ExecuteNonQuery()
        Write-Host "1 voorbeeldverslag toegevoegd aan $DbPath ($SourceTable)."
    }
} finally {
    $conn.Close()
}
