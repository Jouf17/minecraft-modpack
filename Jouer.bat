@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%update-and-play.ps1"

if errorlevel 1 (
    echo.
    echo Une erreur est survenue. La fenetre reste ouverte pour lire le message.
    pause
)
