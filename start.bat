@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ========================================
echo  Categorize-H-Data
echo ========================================
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo Fehler: Python wurde nicht gefunden.
    echo Bitte zuerst Python installieren - siehe INSTALL.md, Abschnitt 1.
    echo.
    pause
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo [Erststart] Lege virtuelle Umgebung an ...
    python -m venv .venv
    if errorlevel 1 (
        echo Fehler beim Anlegen der virtuellen Umgebung.
        pause
        exit /b 1
    )
    echo [Erststart] Installiere Pakete ^(openai, python-dotenv^) ...
    ".venv\Scripts\python.exe" -m pip install --upgrade pip
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo Fehler beim Installieren der Pakete.
        pause
        exit /b 1
    )
    echo.
)

if not exist ".env" (
    echo Fehler: Datei .env fehlt.
    echo Bitte .env.example kopieren, in .env umbenennen
    echo und OPENAI_API_KEY eintragen.
    echo.
    pause
    exit /b 1
)

if not exist "categories.json" (
    echo Fehler: Datei categories.json fehlt.
    echo Bitte categories.example.json kopieren, in categories.json umbenennen
    echo und an die eigenen Kategorien anpassen.
    echo.
    pause
    exit /b 1
)

echo Starte Kategorisierung ...
echo.
".venv\Scripts\python.exe" categorize.py %*
set EXITCODE=%ERRORLEVEL%

echo.
echo ========================================
if %EXITCODE%==0 (
    echo  Fertig. Du kannst das Fenster schliessen.
) else (
    echo  Mit Fehler beendet ^(Code %EXITCODE%^).
)
echo ========================================
pause
exit /b %EXITCODE%
