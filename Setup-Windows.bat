@echo off
REM Vimigo AI Setup - double-click this file.
REM
REM It only starts the setup menu. Nothing is installed until you choose it.

REM Everything else lives in the folder beside this file, so the customer
REM opens the zip and sees two things they might reasonably double-click
REM rather than eighteen files of which sixteen are ours.
setlocal
cd /d "%~dp0Vimigo files"
if errorlevel 1 (
    echo.
    echo   The "Vimigo files" folder is missing.
    echo.
    echo   This happens when only one file was copied out of the zip
    echo   instead of the whole folder. Copy the whole folder and try again.
    echo.
    pause
    exit /b 1
)

REM The setup screen draws box and block characters. Code page 65001 is UTF-8,
REM without which they arrive as mojibake on most machines.
chcp 65001 >nul 2>&1

REM Prefer PowerShell 7 when it is here, but Windows' built-in PowerShell is
REM enough. The setup does not require PowerShell 7 to be installed first.
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "vimigo-setup.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "vimigo-setup.ps1"
)

echo.
pause
