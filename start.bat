@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ========================================
echo  Categorize-H-Data
echo ========================================
echo.

if not exist ".env" (
    echo Fout: bestand .env ontbreekt.
    echo Kopieer .env.example naar .env en vul OPENAI_API_KEY in.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0categorize.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
echo ========================================
if %EXITCODE%==0 (
    echo  Klaar. Je kunt dit venster sluiten.
) else (
    echo  Beeindigd met fout (code %EXITCODE%).
)
echo ========================================
pause
exit /b %EXITCODE%
