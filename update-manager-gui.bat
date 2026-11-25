@echo off
chcp 65001 >nul
REM ============================================
REM Universal Update Manager - window starter
REM SPDX-License-Identifier: GPL-3.0-or-later
REM Copyright (C) 2025-2026 MelucioLabs / David Vaupel
REM ============================================
REM Starts update-manager-gui.ps1 with administrator rights. The window IS
REM the surface - no console behind it.
REM ============================================

title Universal Update Manager

net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunScript
) else (
    echo Administrator-Rechte werden angefordert...
    REM Chip 49, David 25.11.2026: the elevation goes DIRECTLY to the hidden
    REM PowerShell that carries the window, NOT to this .bat again. The old
    REM relaunch of the .bat under RunAs opened a console window that stayed
    REM visible until the WPF window came up. -WorkingDirectory keeps what
    REM the old `cd /d "%~dp0"` did; the return chain rests in the GUI
    REM itself, which reports failures in its own window and in the log.
    REM Chip 52 (25.11.2026): the elevated target runs via -Command with an
    REM & { ... } block instead of a file argument. Elevated + hidden window
    REM plus a file argument died immediately with exit code -196608 on
    REM David's machine (verified in the field); the -Command form opens.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath 'powershell.exe' -Verb RunAs -WorkingDirectory '%~dp0' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-Command','& { Set-Location -LiteralPath ''%~dp0''; & ''%~dp0update-manager-gui.ps1'' }' -ErrorAction Stop; exit 0 } catch { try { Add-Content -Path ($env:ProgramData + '\UpdateManager\universal-update-manager.log') -Value ('[{0}] [START] [ERROR] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) -Encoding UTF8 } catch { }; exit 1 }"
    if errorlevel 1 (
        echo Die Administrator-Rechte wurden verweigert oder der Start schlug fehl.
        echo Protokoll: C:\ProgramData\UpdateManager\universal-update-manager.log
        pause
    )
    exit /b
)

:RunScript
cd /d "%~dp0"
REM Chip 52 (25.11.2026): auch dieser Zweig startet ueber -Command mit
REM & { ... } - bei erhoehter .bat direkt ohne zweite UAC-Abfrage.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& { Set-Location -LiteralPath '%~dp0'; & '%~dp0update-manager-gui.ps1' }"

if %errorlevel% neq 0 (
    echo.
    echo Das Fenster konnte nicht geoeffnet werden.
    echo Protokoll: C:\ProgramData\UpdateManager\universal-update-manager.log
    pause
)

exit /b
