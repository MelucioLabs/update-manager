# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

#Requires -RunAsAdministrator
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Neben das Protokoll des Managers, nicht in einen festen Benutzerordner:
# Der Pfad stand hier frueher auf einen Desktop mit Benutzernamen.
$logDir  = Join-Path $env:ProgramData 'UpdateManager'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'diagnose-result.log'
function Log($msg) { $msg | Tee-Object -FilePath $logFile -Append; }

"" | Set-Content $logFile
Log "=== DIAGNOSE: Silent-Mode Winget ==="
Log "Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log ""

# 1. Winget-Pfad
Log "--- 1. Winget-Pfad ---"
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    Log "Typ:     $($wingetCmd.CommandType)"
    Log "Source:  $($wingetCmd.Source)"
    $ver = & winget --version 2>&1
    Log "Version: $ver"
} else {
    Log "winget NICHT GEFUNDEN!"
    exit
}

# 2. Aktuelle Updates
Log ""
Log "--- 2. Aktuelle Updates (direkt) ---"
$beforeOutput = & winget upgrade --accept-source-agreements 2>&1
$beforeOutput | ForEach-Object { Log "  $_" }

# 3. Test: Start-Process mit Redirect (genau wie Invoke-ProcessWithTimeout)
Log ""
Log "--- 3. Test: Start-Process + Redirect (wie unser Code) ---"
$tmpOut = Join-Path $env:TEMP "um_diag_out.tmp"
$tmpErr = Join-Path $env:TEMP "um_diag_err.tmp"
Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $proc = Start-Process -FilePath "winget.exe" `
        -ArgumentList "upgrade --all --silent --accept-source-agreements --accept-package-agreements" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $exited = $proc.WaitForExit(120000)
    $sw.Stop()

    Log "Prozess beendet: $exited"
    Log "Exit-Code:       $($proc.ExitCode)"
    Log "Dauer:           $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
    Log "PID:             $($proc.Id)"

    Log ""
    Log "--- STDOUT von Start-Process ---"
    if (Test-Path $tmpOut) {
        $out = Get-Content $tmpOut -ErrorAction SilentlyContinue
        if ($out) { $out | ForEach-Object { Log "  $_" } }
        else { Log "  (leer)" }
        Log "  Dateigroesse: $((Get-Item $tmpOut).Length) Bytes"
    } else { Log "  (tmp-Datei nicht erstellt)" }

    Log ""
    Log "--- STDERR von Start-Process ---"
    if (Test-Path $tmpErr) {
        $err = Get-Content $tmpErr -ErrorAction SilentlyContinue
        if ($err) { $err | ForEach-Object { Log "  $_" } }
        else { Log "  (leer)" }
    } else { Log "  (tmp-Datei nicht erstellt)" }
} catch {
    $sw.Stop()
    Log "EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message)"
}
Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

# 4. Updates nochmal pruefen
Log ""
Log "--- 4. Updates NACH Start-Process (weg oder noch da?) ---"
$afterOutput = & winget upgrade --accept-source-agreements 2>&1
$afterOutput | ForEach-Object { Log "  $_" }

# 5. Alternativ: winget direkt im Prozess
Log ""
Log "--- 5. Alternativ-Test: winget direkt (& winget) ---"
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$directOutput = & winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1
$sw2.Stop()
Log "Dauer: $([math]::Round($sw2.Elapsed.TotalSeconds, 1))s"
$directOutput | ForEach-Object { Log "  $_" }

# 6. Final-Check
Log ""
Log "--- 6. Updates NACH Direkt-Aufruf (jetzt weg?) ---"
$finalOutput = & winget upgrade --accept-source-agreements 2>&1
$finalOutput | ForEach-Object { Log "  $_" }

Log ""
Log "=== DIAGNOSE ABGESCHLOSSEN ==="
Write-Host ""
Write-Host "Ergebnis gespeichert in: $logFile" -ForegroundColor Green
Read-Host "Enter zum Beenden"
