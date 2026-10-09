@echo off
chcp 65001 >nul
REM ============================================
REM Universal Update Manager - Fenster-Starter
REM SPDX-License-Identifier: GPL-3.0-or-later
REM Copyright (C) 2025-2026 MelucioLabs / David Vaupel
REM ============================================
REM Startet update-manager-gui.ps1 mit Administratorrechten. Dieselbe
REM Mechanik wie universal-update-manager.bat, nur ohne Konsolenfenster
REM dahinter: Die Oberflaeche IST das Fenster.
REM ============================================

title Universal Update Manager

net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunScript
) else (
    echo Fordere Administrator-Rechte an...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:RunScript
cd /d "%~dp0"

REM -WindowStyle Hidden: Die PowerShell-Konsole bleibt zu, sichtbar ist nur
REM das WPF-Fenster. Ohne das stehen zwei Fenster da, und das graue
REM Konsolenfenster sieht aus, als waere etwas schiefgegangen.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0update-manager-gui.ps1"

if %errorlevel% neq 0 (
    echo.
    echo Das Fenster konnte nicht geoeffnet werden.
    echo Protokoll: C:\ProgramData\UpdateManager\universal-update-manager.log
    pause
)

exit /b
