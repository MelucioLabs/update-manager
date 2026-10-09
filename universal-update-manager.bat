@echo off
chcp 65001 >nul
REM ============================================
REM Universal Update Manager - Starter
REM ============================================
REM Autor: David Vaupel (MelucioLabs), seit 02.11.2025
REM SPDX-License-Identifier: GPL-3.0-or-later
REM Copyright (C) 2025-2026 MelucioLabs / David Vaupel
REM ============================================

title Universal Update Manager

REM Pruefe Admin-Rechte
net session >nul 2>&1
if %errorLevel% == 0 (
    REM Hat bereits Admin-Rechte
    goto :RunScript
) else (
    REM Fordere Admin-Rechte an
    echo Fordere Administrator-Rechte an...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:RunScript
REM Wechsle ins Script-Verzeichnis
cd /d "%~dp0"

REM Starte PowerShell-Script
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0universal-update-manager.ps1"

REM Fenster offen halten falls Fehler
if %errorlevel% neq 0 (
    echo.
    echo Fehler beim Ausfuehren des Scripts!
    echo Bitte Log-Datei pruefen: C:\ProgramData\UpdateManager\universal-update-manager.log
    pause
)

exit /b
