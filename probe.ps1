# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Bausteinprobe fuer den Update-Manager (22.09.2026).

    WOFUER
    Der Manager installiert unbeaufsichtigt Software. Getestet wurde er
    bisher, indem man ihn laufen liess — und das ist der einzige Test, den
    man nicht eben mal macht: Er dauert Minuten, braucht Administratorrechte
    und veraendert die Maschine. Deshalb hat er bis heute GAR keinen Test
    gehabt.

    Diese Probe macht das Gegenteil: Sie startet nichts, aendert nichts und
    braucht keine erhoehte Sitzung. Sie liest die Dateien und prueft die
    Dinge, die schon zweimal schiefgegangen sind:

      1. Syntax   — beide Skripte lassen sich ueberhaupt parsen.
      2. BOM      — die .bat starten `powershell` (5.1), und ohne Byte Order
                    Mark liest 5.1 eine .ps1 als Windows-1252. Aus "geprueft"
                    wird dann "geprÃ¼ft" (passiert am 21.09.2026).
      3. Auftrag  — jeder Name, den das Fenster an `-Auftrag` uebergibt, muss
                    im `switch` des Kerns vorkommen. Sonst tut ein Knopf
                    nichts, ohne dass irgendwo etwas rot wird.
      4. Texte    — jeder `$T['schluessel']` steht in BEIDEN Sprachtabellen.
                    Ein fehlender Schluessel wirft nicht, er liefert eine
                    LEERE Zeichenkette: Die Meldung verschwindet einfach.
      5. Fenster   — die Oberflaeche baut sich auf, hell wie dunkel.
      6. Job       — Zeitueberschreitung, Fehler und leeres Ergebnis werden
                     auseinandergehalten (drei Ausgaenge, nicht einer).
      7. Letzter Lauf — die Zeile im Fenster liest das Richtige.
      8. Meldung   — schweigt, wo sie soll, und klagt, wo etwas fehlt.
      9. Konfig    — update-config.json ist lesbar und hat ihre Abschnitte.

    Seit dem 03.10.2026 dazu, jeweils in beide Richtungen (greift, wenn es
    soll; schweigt, wenn nicht) und immer gegen Attrappen:

      3b. Mehrere Auftraege aus dem Fenster kommen als mehrere an.
      3c. Ein Lauf mit Fehlern endet nicht gruen (Kern, Fensterzeile, Fenster).
      9b. Der stille Lauf: keine Liste ist kein "nichts offen", Benutzer-
          Pakete werden nachgeholt, [SILENT-DONE] nur ohne Fehler.
      9c. Windows Update nennt optionale Updates und laedt nichts ungefragt.
      9d. Zeitgrenze beendet den ganzen Prozessbaum und sagt, was sie mass.
      9e. Das Protokoll haelt sieben Tage.

    AUFRUF
      pwsh -File probe.ps1            (auch Windows PowerShell 5.1 geht)
      pwsh -File probe.ps1 -Leise     nur die Zusammenfassung

    Im Monorepo NICHT in der CI: Die eigenen Runner sind Linux und haben kein
    pwsh. Im oeffentlichen Repo (MelucioLabs/update-manager) laeuft sie vor
    jedem Release auf einem Windows-Runner (.github/workflows/release.yml).
    Die Probe gehoert trotzdem vor das Weitergeben und hinter jede Aenderung
    von Hand.
#>
param([switch]$Leise)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Ordner = Split-Path -Parent $MyInvocation.MyCommand.Path
$Kern   = Join-Path $Ordner 'universal-update-manager.ps1'
$Gui    = Join-Path $Ordner 'update-manager-gui.ps1'
$Konfig = Join-Path $Ordner 'update-config.json'

$Fehler = New-Object System.Collections.Generic.List[string]
$Zeilen = New-Object System.Collections.Generic.List[string]

function Melde($zeichen, $text) {
    $Zeilen.Add("$zeichen $text")
    if (-not $Leise) {
        $farbe = if ($zeichen -eq 'ok') { 'Green' } elseif ($zeichen -eq '--') { 'DarkGray' } else { 'Red' }
        Write-Host ("  {0}  {1}" -f $zeichen, $text) -ForegroundColor $farbe
    }
}
function Schlecht($text) { $Fehler.Add($text); Melde 'ROT' $text }

Write-Host ""
Write-Host "Bausteinprobe Update-Manager" -ForegroundColor Cyan
Write-Host "----------------------------" -ForegroundColor Cyan

# ── 1. Syntax ───────────────────────────────────────────────────────────────
foreach ($datei in @($Kern, $Gui)) {
    $name = Split-Path -Leaf $datei
    if (-not (Test-Path $datei)) { Schlecht "$name fehlt"; continue }
    $fehlerliste = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($datei, [ref]$null, [ref]$fehlerliste)
    if ($fehlerliste -and $fehlerliste.Count -gt 0) {
        Schlecht "$name hat $($fehlerliste.Count) Syntaxfehler, erster: $($fehlerliste[0].Message)"
    } else {
        Melde 'ok' "$name laesst sich parsen"
    }
}

# ── 2. BOM ──────────────────────────────────────────────────────────────────
# Geprueft werden nur die Dateien, die eine .bat mit `powershell` startet.
#
# Im Monorepo prueft das der Pre-Commit ohnehin fuer ALLE .ps1
# (packages/@meluciolabs/backend-utils/scripts/pruefe-ps1-bom.mjs). Hier steht
# es trotzdem, weil dieser Ordner auch ausserhalb des Repos weitergegeben
# wird — dort gibt es keinen Hook, und ohne BOM bricht als Erstes die
# Oberflaeche.
foreach ($datei in @($Kern, $Gui)) {
    $name = Split-Path -Leaf $datei
    if (-not (Test-Path $datei)) { continue }
    $kopf = [System.IO.File]::ReadAllBytes($datei) | Select-Object -First 3
    if ($kopf.Count -ge 3 -and $kopf[0] -eq 0xEF -and $kopf[1] -eq 0xBB -and $kopf[2] -eq 0xBF) {
        Melde 'ok' "$name hat ein BOM (Windows PowerShell 5.1 liest die Umlaute richtig)"
    } else {
        Schlecht "$name hat KEIN BOM — 5.1 liest die Datei als Windows-1252, Umlaute brechen"
    }
}

# ── 3. Auftragsnamen: Fenster gegen Kern ────────────────────────────────────
if ((Test-Path $Kern) -and (Test-Path $Gui)) {
    $kernText = Get-Content $Kern -Raw
    $guiText  = Get-Content $Gui  -Raw

    # Die Zweige des switch in Invoke-Auftrag: Zeilen der Form  'name' { ...
    $anfang = $kernText.IndexOf('function Invoke-Auftrag')
    $block  = if ($anfang -ge 0) { $kernText.Substring($anfang) } else { '' }
    $bekannt = [regex]::Matches($block, "(?m)^\s*'([a-z]+)'\s*\{") | ForEach-Object { $_.Groups[1].Value }
    $bekannt = $bekannt | Select-Object -Unique

    # Was das Fenster schickt: Es baut die Namen als Liste zusammen
    # (`@{ Name = 'winget'; Titel = … }`) und haengt sie an `-Auftrag`. Also
    # werden die Namen dort gelesen, wo sie stehen, statt am Aufrufpunkt —
    # dort steht nur noch eine Variable.
    $geschickt = [regex]::Matches($guiText, "Name\s*=\s*'([a-z]+)'") | ForEach-Object { $_.Groups[1].Value }
    $geschickt = $geschickt | Where-Object { $_ } | Select-Object -Unique

    if (-not $bekannt) {
        Schlecht "im Kern keine Auftragsnamen gefunden — hat sich der Aufbau von Invoke-Auftrag geaendert?"
    } elseif (-not $geschickt) {
        Melde '--' "das Fenster uebergibt keine festen Auftragsnamen (Variable statt Text?) — nicht pruefbar"
    } else {
        foreach ($n in $geschickt) {
            if ($bekannt -contains $n) { Melde 'ok' "Auftrag '$n' gibt es im Kern" }
            else { Schlecht "das Fenster ruft Auftrag '$n', den der Kern nicht kennt" }
        }
    }
}

# ── 3b. Mehrere Auftraege kommen als mehrere an ─────────────────────────────
#
# Bis zum 03.10.2026 haengte das Fenster die Namen ohne Anfuehrungszeichen an
# `-Command`; aus `winget,choco` wurde am `[string]`-Parameter "winget choco",
# und der Kern trennte nur an Komma und Semikolon. Zwei Schalter ergaben
# "Unbekannter Auftrag". Abschnitt 3 oben sah das nicht: Er vergleicht Namen,
# nicht den Weg, auf dem sie ankommen.
#
# Hier wird der Weg selbst gegangen: Die Zeile, die das Fenster baut, startet
# einen echten Prozess — nur gegen eine Attrappe statt gegen den Kern. Die
# Attrappe hat denselben Parameter und dieselbe Zerlegefunktion.
function Hole-Funktion {
    param([string]$Datei, [string[]]$Namen)
    $b = [System.Management.Automation.Language.Parser]::ParseFile($Datei, [ref]$null, [ref]$null)
    $gefunden = @($b.FindAll({
        param($k) $k -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Namen -contains $k.Name
    }.GetNewClosure(), $true))
    if ($gefunden.Count -lt $Namen.Count) { return $null }
    return ($gefunden | ForEach-Object { $_.Extent.Text }) -join "`n"
}

function Starte-Still {
    # Wie das Fenster: ohne Konsole, Ausgabe umgeleitet.
    param([string]$Exe, [string]$Argumente)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $Exe
    $psi.Arguments = $Argumente
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $fehlerLesen = $p.StandardError.ReadToEndAsync()
    $aus = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ Ausgabe = $aus; Fehler = $fehlerLesen.Result; ExitCode = $p.ExitCode }
}

# Die Shells, mit denen der Manager wirklich laeuft: die .bat startet
# Windows PowerShell 5.1, die Aufgabenplanung pwsh 7, wenn es da ist.
$Shells = @((Get-Process -Id $PID).Path)
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ((Test-Path $ps51) -and ($Shells -notcontains $ps51)) { $Shells += $ps51 }

if ((Test-Path $Kern) -and (Test-Path $Gui)) {
    $fnBau   = Hole-Funktion $Gui  @('Baue-KernArgumente')
    $fnSplit = Hole-Funktion $Kern @('Split-Auftrag')
    if (-not $fnBau) {
        Schlecht "Baue-KernArgumente fehlt im Fenster — die Argumentzeile ist nicht pruefbar"
    } elseif (-not $fnSplit) {
        Schlecht "Split-Auftrag fehlt im Kern — die Zerlegung ist nicht pruefbar"
    } else {
        # Als Skriptbloecke gerufen, nicht per Punkt eingelesen: Der
        # Aufruf-Waechter im Pre-Commit sieht sonst einen Funktionsnamen, den
        # diese Datei nirgends definiert, und haelt ihn fuer einen Ruf ins
        # Leere.
        $baue    = [scriptblock]::Create($fnBau   + "`nBaue-KernArgumente -KernPfad `$args[0] -Namen `$args[1]")
        $zerlege = [scriptblock]::Create($fnSplit + "`n(Split-Auftrag `$args[0]) -join '|'")

        # Erst die Zerlegung allein, in beide Richtungen.
        $zerlegt = @(
            @{ Ein = 'winget,choco';      Soll = 'winget|choco' }
            @{ Ein = 'winget choco';      Soll = 'winget|choco' }   # so kam es an
            @{ Ein = 'winget; store ,';   Soll = 'winget|store' }
            @{ Ein = 'winget';            Soll = 'winget' }         # einer bleibt einer
        )
        $falsch = @($zerlegt | Where-Object { (& $zerlege $_.Ein) -ne $_.Soll })
        if ($falsch.Count -eq 0) { Melde 'ok' "Auftraege werden an Komma, Semikolon und Leerraum getrennt" }
        else { Schlecht "Zerlegung falsch bei: $(($falsch | ForEach-Object { "'$($_.Ein)'" }) -join ', ')" }

        # Dann der ganze Weg. Der Ordner traegt ein Leerzeichen und ein
        # Hochkomma: beides kommt in Benutzerpfaden vor.
        $probeOrdner = Join-Path ([System.IO.Path]::GetTempPath()) ("um probe's {0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $probeOrdner -Force | Out-Null
        $attrappe = Join-Path $probeOrdner 'kern-attrappe.ps1'
        $inhalt = "param([string]`$Auftrag)`n$fnSplit`n" +
                  "Write-Output ('NAMEN=' + ((Split-Auftrag `$Auftrag) -join '|'))`n"
        [System.IO.File]::WriteAllText($attrappe, $inhalt, (New-Object System.Text.UTF8Encoding $true))
        try {
            foreach ($shell in $Shells) {
                $kurz = [System.IO.Path]::GetFileNameWithoutExtension($shell)
                foreach ($fall in @(
                    @{ Namen = @('winget', 'choco');                              Soll = 'NAMEN=winget|choco' }
                    @{ Namen = @('winget', 'choco', 'windows', 'store', 'treiber'); Soll = 'NAMEN=winget|choco|windows|store|treiber' }
                    @{ Namen = @('pruefen');                                      Soll = 'NAMEN=pruefen' }
                )) {
                    $r = Starte-Still $shell (& $baue $attrappe $fall.Namen)
                    $kam = ($r.Ausgabe -split "`r?`n" | Where-Object { $_ -like 'NAMEN=*' } | Select-Object -Last 1)
                    if ($kam -eq $fall.Soll) {
                        Melde 'ok' "Fensterzeile mit $($fall.Namen.Count) Auftrag/Auftraegen kommt richtig an ($kurz)"
                    } else {
                        Schlecht "Fensterzeile mit '$($fall.Namen -join ',')' kommt falsch an ($kurz): '$kam' $($r.Fehler)"
                    }
                }
            }
        } finally {
            # Datei, dann der leere Ordner: kein rekursives Loeschen ueber
            # eine Variable.
            Remove-Item -LiteralPath $attrappe -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $probeOrdner -ErrorAction SilentlyContinue
        }
    }
}

# ── 3c. Ein Lauf mit Fehlern endet nicht gruen ──────────────────────────────
#
# Bis zum 03.10.2026 endete der Auftragsmodus immer mit `exit 0`, und das
# Fenster las den Exit-Code ohnehin nicht: "Fertig" in Gruen, egal was war.
# Geprueft wird die ganze Kette in beide Richtungen — der Kern zaehlt Fehler
# (und nur Fehler), die Fensterzeile reicht den Code durch, und das Fenster
# macht daraus Gruen oder Rot.
if ((Test-Path $Kern) -and (Test-Path $Gui)) {
    # (a) Der Kern: Fehler zaehlen, Warnungen nicht.
    $fnZaehl = Hole-Funktion $Kern @('Write-Log', 'Get-LaufExitCode')
    if (-not $fnZaehl) {
        Schlecht "Write-Log oder Get-LaufExitCode fehlt im Kern — der Exit-Code haengt an nichts"
    } else {
        $vorspannZ = "`$LogFile = [System.IO.Path]::GetTempFileName()`n" +
                     "`$ColorSuccess='Green'; `$ColorError='Red'; `$ColorWarning='Yellow'; `$ColorInfo='Cyan'`n" +
                     "`$Global:FehlerImLauf = 0`n" + $fnZaehl + "`n"
        $nachspannZ = "`nRemove-Item -LiteralPath `$LogFile -ErrorAction SilentlyContinue`n`$code"
        $ohne = & ([scriptblock]::Create($vorspannZ + "Write-Log 'a' 'WARNING' 6>`$null; Write-Log 'b' 'SUCCESS' 6>`$null; `$code = Get-LaufExitCode" + $nachspannZ))
        $mit  = & ([scriptblock]::Create($vorspannZ + "Write-Log 'a' 'WARNING' 6>`$null; Write-Log 'b' 'ERROR' 6>`$null; `$code = Get-LaufExitCode" + $nachspannZ))
        if ($ohne -eq 0) { Melde 'ok' "ein Lauf ohne Fehler endet mit 0 (Warnungen faerben nicht rot)" }
        else { Schlecht "ein Lauf ohne Fehler endet mit $ohne statt 0" }
        if ($mit -ne 0) { Melde 'ok' "ein Lauf mit Fehler endet mit $mit statt 0" }
        else { Schlecht "ein Lauf mit protokolliertem Fehler endet trotzdem mit 0 — das falsche Gruen" }
    }

    $kernText3c = Get-Content $Kern -Raw
    if ($kernText3c -match 'Invoke-Auftrag -Namen \$namen\s+exit \(Get-LaufExitCode\)') {
        Melde 'ok' "der Auftragsmodus endet mit dem gezaehlten Code, nicht mit festem 0"
    } else {
        Schlecht "der Auftragsmodus endet nicht mit Get-LaufExitCode — er meldet wieder immer Erfolg"
    }

    # (b) Die Fensterzeile reicht den Code durch.
    $fnBau2 = Hole-Funktion $Gui @('Baue-KernArgumente')
    if ($fnBau2) {
        $baue2 = [scriptblock]::Create($fnBau2 + "`nBaue-KernArgumente -KernPfad `$args[0] -Namen `$args[1]")
        $ordner2 = Join-Path ([System.IO.Path]::GetTempPath()) ("um-exit-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $ordner2 -Force | Out-Null
        $attrappe2 = Join-Path $ordner2 'kern-attrappe.ps1'
        $inhalt2 = "param([string]`$Auftrag)`n" +
                   "if (`$Auftrag -match 'choco') { exit 5 }`n" +
                   "if (`$Auftrag -match 'store') { throw 'absichtlich kaputt' }`n" +
                   "exit 0`n"
        [System.IO.File]::WriteAllText($attrappe2, $inhalt2, (New-Object System.Text.UTF8Encoding $true))
        try {
            foreach ($shell in $Shells) {
                $kurz = [System.IO.Path]::GetFileNameWithoutExtension($shell)
                $gut    = (Starte-Still $shell (& $baue2 $attrappe2 @('winget'))).ExitCode
                $fehler5 = (Starte-Still $shell (& $baue2 $attrappe2 @('winget', 'choco'))).ExitCode
                $wurf   = (Starte-Still $shell (& $baue2 $attrappe2 @('store'))).ExitCode
                $fehlt  = (Starte-Still $shell (& $baue2 (Join-Path $ordner2 'gibt-es-nicht.ps1') @('winget'))).ExitCode
                if ($gut -eq 0) { Melde 'ok' "Fensterzeile: gelungener Lauf kommt als 0 an ($kurz)" }
                else { Schlecht "Fensterzeile: gelungener Lauf kommt als $gut an ($kurz)" }
                if ($fehler5 -eq 5) { Melde 'ok' "Fensterzeile: Exit 5 des Kerns kommt als 5 an ($kurz)" }
                else { Schlecht "Fensterzeile: Exit 5 des Kerns kommt als $fehler5 an ($kurz)" }
                if ($wurf -ne 0 -and $fehlt -ne 0) { Melde 'ok' "Fensterzeile: Absturz und fehlende Datei sind nicht 0 (${kurz}: $wurf, $fehlt)" }
                else { Schlecht "Fensterzeile: Absturz ($wurf) oder fehlende Datei ($fehlt) kommt als Erfolg an ($kurz)" }
            }
        } finally {
            Remove-Item -LiteralPath $attrappe2 -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $ordner2 -ErrorAction SilentlyContinue
        }
    }

    # (c) Das Fenster macht daraus Gruen oder Rot.
    $fnSchluss = Hole-Funktion $Gui @('Bilde-Abschluss')
    $guiText3c = Get-Content $Gui -Raw
    if (-not $fnSchluss) {
        Schlecht "Bilde-Abschluss fehlt im Fenster — das Ende eines Laufs ist nicht pruefbar"
    } else {
        $schluss = [scriptblock]::Create($fnSchluss + "`nBilde-Abschluss -Art `$args[0] -ExitCode `$args[1] -Minuten 1.5")
        $f = @(
            @{ Art = 'alles';   Code = 0;  Gut = $true  }
            @{ Art = 'pruefen'; Code = 0;  Gut = $true  }
            @{ Art = 'alles';   Code = 5;  Gut = $false }
            @{ Art = 'alles';   Code = 2;  Gut = $false }
            @{ Art = 'pruefen'; Code = 5;  Gut = $false }
            @{ Art = 'alles';   Code = -1; Gut = $false }
        )
        $daneben = @($f | Where-Object {
            $s = & $schluss $_.Art $_.Code
            ($s.Gut -ne $_.Gut) -or (-not $_.Gut -and $s.Status -notmatch 'Protokoll')
        })
        if ($daneben.Count -eq 0) { Melde 'ok' "Fenster: Code 0 ist gruen, alles andere rot mit Verweis aufs Protokoll" }
        else { Schlecht "Fenster wertet Exit-Codes falsch: $(($daneben | ForEach-Object { "$($_.Art)/$($_.Code)" }) -join ', ')" }
    }
    if ($guiText3c -match 'MARKE_FERTIG \+ \$prozess\.ExitCode') {
        Melde 'ok' "das Fenster liest den Exit-Code des Kerns"
    } else {
        Schlecht "das Fenster liest den Exit-Code des Kerns nicht — es meldet wieder immer 'Fertig'"
    }
}

# ── 4. Sprachschluessel ─────────────────────────────────────────────────────
if (Test-Path $Kern) {
    $kernText = Get-Content $Kern -Raw
    $benutzt = [regex]::Matches($kernText, "\`$T\['([a-zA-Z0-9_]+)'\]") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    # Die beiden Tabellen stehen als Zuweisungen "schluessel" = "text" in je
    # einem Block; gezaehlt wird, wie oft ein Schluessel DEFINIERT wird.
    $fehlend = @()
    $halb    = @()
    foreach ($s in $benutzt) {
        $treffer = [regex]::Matches($kernText, "(?m)^\s*`"$s`"\s*=").Count
        if     ($treffer -eq 0) { $fehlend += $s }
        elseif ($treffer -lt 2) { $halb    += $s }
    }
    if ($fehlend) { Schlecht "$($fehlend.Count) Textschluessel fehlen ganz: $($fehlend -join ', ')" }
    if ($halb)    { Schlecht "$($halb.Count) Textschluessel stehen nur in EINER Sprache: $($halb -join ', ')" }
    if (-not $fehlend -and -not $halb) {
        Melde 'ok' "alle $($benutzt.Count) Textschluessel stehen in beiden Sprachtabellen"
    }
}

# ── 5. Das Fenster baut sich auf, hell wie dunkel ───────────────────────────
# Der Blindtest der Oberflaeche (`-NurPruefen`) oeffnet nichts und braucht
# seit dem 22.09.2026 keine erhoehte Sitzung mehr — vorher stand `#Requires
# -RunAsAdministrator` in der Datei und sperrte damit auch den Test aus.
if (Test-Path $Gui) {
    foreach ($art in @('hell', 'dunkel')) {
        $ausgabe = & (Get-Process -Id $PID).Path -NoProfile -File $Gui -NurPruefen -Erscheinung $art 2>&1
        if ($LASTEXITCODE -eq 0) {
            Melde 'ok' "Fenster baut sich auf ($art): $($ausgabe | Select-Object -First 1)"
        } else {
            Schlecht "Fenster laesst sich nicht aufbauen ($art): $($ausgabe | Select-Object -Last 1)"
        }
    }

    # Und einmal MIT Nachladen: Hardware und Aufgabenplanung holt das Fenster
    # seit dem 23.09.2026 nebenher (vorher stand es dafuer 4,4 s still). Der
    # Blindtest oben endet vor diesem Teil und waere blind fuer genau den
    # Umbau; `-Selbsttest` dreht die Nachrichtenschleife von Hand und prueft,
    # dass beide Zeilen wirklich ankommen.
    $st = & (Get-Process -Id $PID).Path -NoProfile -File $Gui -Selbsttest 2>&1
    if ($LASTEXITCODE -eq 0) {
        Melde 'ok' "Nachladen kommt im Fenster an ($(($st | Select-Object -First 1)))"
    } else {
        Schlecht "Nachladen kommt nicht an: $($st -join ' / ')"
    }
}

# ── 6. Verhalten: die drei Ausgaenge eines Jobs ─────────────────────────────
#
# Die einzige Stelle im Manager, die wirklich LAEUFT statt gelesen zu werden.
# Sie ist es wert: Bis zum 22.09.2026 gab `Run-JobWithTimeout` fuer
# Zeitueberschreitung, Fehler und leeres Ergebnis dasselbe `$null` zurueck,
# und die Aufrufer nannten alles "Timeout" — 74-mal im Protokoll, obwohl
# zwischen Start und Meldung teils 15 Sekunden lagen.
#
# Geholt werden die beiden Funktionen ueber den Parser aus der Datei, damit
# der Manager selbst nicht startet (er wuerde sein Menue oeffnen).
if (Test-Path $Kern) {
    $baum = [System.Management.Automation.Language.Parser]::ParseFile($Kern, [ref]$null, [ref]$null)
    $gesucht = @('Run-JobWithTimeout', 'Lies-JobAusgabe')
    $quelle = ($baum.FindAll({
        param($k) $k -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $gesucht -contains $k.Name
    }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"

    if (($quelle -split 'function ').Count - 1 -lt 2) {
        Schlecht "Run-JobWithTimeout oder Lies-JobAusgabe nicht gefunden — Aufbau geaendert?"
    } else {
        $pruefblock = @'
$T = @{ job_fehler = 'Abfrage fehlgeschlagen'; job_grenze = 'Zeitgrenze'; test = 'Zeit' }
$script:Gemeldet = @()
function Write-Log { param($t, $s) $script:Gemeldet += "$s|$t" }
__FUNKTIONEN__
$e = @{}
$e.ok    = Run-JobWithTimeout -ScriptBlock { 'hallo' }              -TimeoutSeconds 30
$e.leer  = Run-JobWithTimeout -ScriptBlock { }                      -TimeoutSeconds 30
$e.fehl  = Run-JobWithTimeout -ScriptBlock { throw 'absichtlich' }  -TimeoutSeconds 30
$e.zeit  = Run-JobWithTimeout -ScriptBlock { Start-Sleep -Seconds 8 } -TimeoutSeconds 2
$aus = @{}
foreach ($k in 'ok','leer','fehl','zeit') { $aus[$k] = Lies-JobAusgabe $e[$k] $T['test'] 2 }
[pscustomobject]@{
    Zustaende   = ($e.Keys | Sort-Object | ForEach-Object { "$_=$($e[$_].Zustand)" }) -join ' '
    LeerIstKeinAbbruch = ($null -ne $aus['leer'])
    FehlerBricht       = ($null -eq $aus['fehl'])
    ZeitBricht         = ($null -eq $aus['zeit'])
    FehlerTextDrin     = [bool]($script:Gemeldet -match 'absichtlich')
    Meldungen          = $script:Gemeldet -join ' / '
} | ConvertTo-Json -Compress
'@
        $pruefblock = $pruefblock.Replace('__FUNKTIONEN__', $quelle)
        $datei = Join-Path ([System.IO.Path]::GetTempPath()) ("um-jobprobe-{0}.ps1" -f [guid]::NewGuid())
        Set-Content -LiteralPath $datei -Value $pruefblock -Encoding UTF8
        try {
            $roh = & (Get-Process -Id $PID).Path -NoProfile -File $datei 2>&1
            $r = $roh | Select-Object -Last 1 | ConvertFrom-Json
            $soll = 'fehl=fehler leer=leer ok=ok zeit=zeit'
            if ($r.Zustaende -eq $soll) { Melde 'ok' "Job-Zustaende unterschieden: $($r.Zustaende)" }
            else { Schlecht "Job-Zustaende falsch: $($r.Zustaende) (erwartet: $soll)" }

            if ($r.LeerIstKeinAbbruch) { Melde 'ok' "leeres Ergebnis ist kein Abbruch (heisst: nichts offen)" }
            else { Schlecht "leeres Ergebnis wird als Abbruch behandelt — das war der alte Fehler" }

            if ($r.FehlerBricht -and $r.FehlerTextDrin) { Melde 'ok' "ein Fehler bricht ab UND nennt seinen Text" }
            else { Schlecht "Fehler wird verschluckt oder ohne Text gemeldet: $($r.Meldungen)" }

            if ($r.ZeitBricht) { Melde 'ok' "Zeitueberschreitung bricht ab" }
            else { Schlecht "Zeitueberschreitung bricht nicht ab" }
        } catch {
            Schlecht "Job-Probe liess sich nicht auswerten: $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $datei -ErrorAction SilentlyContinue
        }
    }
}

# ── 7. Die Zeile über den letzten stillen Lauf ──────────────────────────────
# Gegen ein erfundenes Protokoll, nicht gegen das echte: Das echte sieht
# heute so aus und morgen anders, und ein Test, der vom Tag abhängt, ist
# keiner.
if (Test-Path $Gui) {
    $baum2 = [System.Management.Automation.Language.Parser]::ParseFile($Gui, [ref]$null, [ref]$null)
    $fn = ($baum2.FindAll({
        param($k) $k -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $k.Name -eq 'Lies-LetztenLauf'
    }, $true) | ForEach-Object { $_.Extent.Text })

    if (-not $fn) {
        Schlecht "Lies-LetztenLauf nicht gefunden — Aufbau des Fensters geaendert?"
    } else {
        $probelog = Join-Path ([System.IO.Path]::GetTempPath()) ("um-log-{0}.log" -f [guid]::NewGuid())
        @(
            '[2026-09-01 04:00:00] [INFO] Silent Mode gestartet',
            '[2026-09-01 04:00:10] [ERROR] uralter Fehler, gehoert NICHT in die Zeile',
            '[2026-09-01 04:01:00] [INFO] [SILENT-DONE] Silent Mode abgeschlossen. Dauer: 1 Minuten',
            '[2026-09-02 04:00:00] [INFO] Silent Mode gestartet',
            '[2026-09-02 04:03:00] [SUCCESS] Aktualisiert: Werkzeug A, Werkzeug B (2 Updates)',
            '[2026-09-02 04:04:00] [INFO] [SILENT-DONE] Silent Mode abgeschlossen. Dauer: 4 Minuten'
        ) | Set-Content -LiteralPath $probelog -Encoding UTF8
        try {
            $zeile = & ([scriptblock]::Create($fn + "`nLies-LetztenLauf '$probelog'"))
            if ($zeile -match '2026-09-02' -and $zeile -match 'Werkzeug A') {
                Melde 'ok' "letzter Lauf wird gelesen: $zeile"
            } else {
                Schlecht "letzter Lauf falsch gelesen: $zeile"
            }
            if ($zeile -notmatch 'Fehler') {
                Melde 'ok' "ein Fehler aus einem AELTEREN Lauf faerbt die Zeile nicht"
            } else {
                Schlecht "Fehler aus einem frueheren Lauf steht in der Zeile: $zeile"
            }

            # Ein GESCHEITERTER Lauf ist auch der letzte Lauf: Er schreibt
            # [SILENT-FAILED], und die Zeile darf dann nicht den guten Lauf
            # von davor zeigen.
            Add-Content -LiteralPath $probelog -Encoding UTF8 -Value @(
                '[2026-09-03 04:00:00] [INFO] Silent Mode gestartet',
                '[2026-09-03 04:01:00] [ERROR] Winget antwortet nicht (Timeout)',
                '[2026-09-03 04:02:00] [ERROR] [SILENT-FAILED] Silent Mode mit Fehlern beendet. Dauer: 2 Minuten'
            )
            $zeile2 = & ([scriptblock]::Create($fn + "`nLies-LetztenLauf '$probelog'"))
            if ($zeile2 -match '2026-09-03' -and $zeile2 -match 'gescheitert' -and $zeile2 -notmatch 'Werkzeug A') {
                Melde 'ok' "ein gescheiterter Lauf steht als solcher in der Zeile: $zeile2"
            } else {
                Schlecht "gescheiterter Lauf wird uebergangen oder schoengefaerbt: $zeile2"
            }
        } finally {
            Remove-Item -LiteralPath $probelog -ErrorAction SilentlyContinue
        }
    }
}

# ── 8. Meldung: schweigt richtig, klagt richtig ─────────────────────────────
# Kein Netz noetig: Geprueft werden die drei Wege VOR dem Senden. Der
# gefaehrlichste ist der letzte — eine eingeschaltete Meldung ohne
# Zugangsdatei darf nicht stillschweigend nichts tun.
if (Test-Path $Kern) {
    $baum3 = [System.Management.Automation.Language.Parser]::ParseFile($Kern, [ref]$null, [ref]$null)
    $fnSend = ($baum3.FindAll({
        param($k) $k -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $k.Name -eq 'Send-Meldung'
    }, $true) | ForEach-Object { $_.Extent.Text })

    if (-not $fnSend) {
        Schlecht "Send-Meldung nicht gefunden — Aufbau geaendert?"
    } else {
        $vorspann = @'
$T = @{ push_ohne_adresse = 'ohne Adresse'; push_ohne_zugang = 'ohne Zugangsdatei'; push_fehler = 'Meldung fehlgeschlagen' }
$script:Gemeldet = @()
function Write-Log { param($m, $l) $script:Gemeldet += "$l|$m" }
'@
        $faelle = @(
            @{ Name = 'aus';        Cfg = '@{ benachrichtigung = [pscustomobject]@{ enabled = $false } }'; Soll = 'still' }
            @{ Name = 'fehlt ganz'; Cfg = '@{ }';                                                          Soll = 'still' }
            @{ Name = 'ohne Adresse'; Cfg = '@{ benachrichtigung = [pscustomobject]@{ enabled = $true; url = "" } }'; Soll = 'meldet' }
            @{ Name = 'ohne Zugangsdatei'; Cfg = '@{ benachrichtigung = [pscustomobject]@{ enabled = $true; url = "http://127.0.0.1:1/x"; authDatei = "C:\gibtesnicht\.ntfy-auth" } }'; Soll = 'meldet' }
        )
        foreach ($f in $faelle) {
            $code = $vorspann + "`n" + $fnSend + "`n" +
                    '$Global:Config = [pscustomobject]' + $f.Cfg + "`n" +
                    '$r = Send-Meldung -Titel "t" -Text "t"' + "`n" +
                    '[pscustomobject]@{ Ergebnis = $r; Meldungen = ($script:Gemeldet -join " / ") } | ConvertTo-Json -Compress'
            try {
                $a = & ([scriptblock]::Create($code)) | ConvertFrom-Json
                $geredet = -not [string]::IsNullOrWhiteSpace($a.Meldungen)
                if ($f.Soll -eq 'still' -and -not $a.Ergebnis -and -not $geredet) {
                    Melde 'ok' "Meldung '$($f.Name)': schweigt, wie sie soll"
                } elseif ($f.Soll -eq 'meldet' -and -not $a.Ergebnis -and $geredet) {
                    Melde 'ok' "Meldung '$($f.Name)': sagt Bescheid statt still zu versagen"
                } else {
                    Schlecht "Meldung '$($f.Name)' verhaelt sich falsch (Ergebnis=$($a.Ergebnis), Log='$($a.Meldungen)')"
                }
            } catch {
                Schlecht "Meldung '$($f.Name)' liess sich nicht pruefen: $($_.Exception.Message)"
            }
        }
    }
}

# ── 9. Eine Zeitueberschreitung zaehlt als Fehler ───────────────────────────
#
# In der Nacht auf den 24.09.2026 wurde winget nach 300 s abgeschnitten, drei
# Pakete blieben offen — und es kam KEINE Meldung, weil der Abbruch nur eine
# Warnung war. Genau dieser Fall ist der, fuer den die Meldung existiert.
# Geprueft wird am Quelltext: Jeder `TimedOut`-Zweig im stillen Lauf muss die
# Fehlerliste fuellen, denn nur sie loest die Meldung aus.
if (Test-Path $Kern) {
    # NICHT `$zeilen` nennen: PowerShell unterscheidet keine Gross- und
    # Kleinschreibung bei Variablen, und `$Zeilen` ist die Sammelliste dieser
    # Probe. Der erste Anlauf hat sie damit ueberschrieben, und die Probe starb
    # mit "Collection was of a fixed size".
    $kernZeilen = Get-Content $Kern
    $stellen = @()
    for ($i = 0; $i -lt $kernZeilen.Count; $i++) {
        if ($kernZeilen[$i] -notmatch '\.TimedOut\)\s*\{') { continue }
        # `-not ….TimedOut` ist der GEGENTEILIGE Zweig (der Normalfall) und
        # braucht keinen Fehlereintrag. Ohne diese Zeile meldete der Pruefer
        # ihn als Fund.
        if ($kernZeilen[$i] -match '-not\s+\$\w+\.TimedOut') { continue }

        # GENAU DER ZWEIG, nicht "die naechsten N Zeilen". Ein festes Fenster
        # war beim zweiten Anlauf zu kurz (der Begruendungs-Kommentar passte
        # nicht hinein, falscher Alarm) und beim dritten zu lang: Es fand das
        # `$errors +=` aus dem FOLGENDEN Block und meldete gruen, obwohl die
        # Zeile fehlte. Also Klammern zaehlen und beim Ausgleich aufhoeren.
        $tiefe = 0; $rumpf = @(); $j = $i
        do {
            $zeile = $kernZeilen[$j]
            $tiefe += ([regex]::Matches($zeile, '\{')).Count
            $tiefe -= ([regex]::Matches($zeile, '\}')).Count
            $rumpf += $zeile
            $j++
        } while ($tiefe -gt 0 -and $j -lt $kernZeilen.Count -and ($j - $i) -lt 60)

        if (($rumpf -join "`n") -notmatch '\$errors\s*\+=') { $stellen += ($i + 1) }
    }
    if ($stellen.Count -eq 0) {
        Melde 'ok' "jede Zeitueberschreitung fuellt die Fehlerliste (und loest damit die Meldung aus)"
    } else {
        Schlecht "Zeitueberschreitung ohne Eintrag in die Fehlerliste, Zeile(n): $($stellen -join ', ') — ein stiller Stillstand"
    }
}

# ── 9b. Der stille Lauf sagt die Wahrheit ───────────────────────────────────
#
# Der einzige Teil, der nachts ohne Zuschauer laeuft, hatte keinen einzigen
# Verhaltenstest. Am 03.10.2026 stand deshalb im Protokoll "Winget antwortet
# nicht" und eine Zeile darunter "Keine Updates verfuegbar" in Gruen; stripe
# wurde 35-mal gefunden und nie aktualisiert, und unter einem gescheiterten
# Lauf stand trotzdem [SILENT-DONE].
#
# Invoke-SilentUpdate laeuft hier WIRKLICH — aber gegen Attrappen: Keine der
# Funktionen, die winget, choco, die Aufgabenplanung oder das Netz anfassen,
# ist die echte. Geprueft wird, was im Protokoll landet.
if (Test-Path $Kern) {
    $fnStill = Hole-Funktion $Kern @('Invoke-SilentUpdate', 'Lies-JobAusgabe')
    if (-not $fnStill) {
        Schlecht "Invoke-SilentUpdate oder Lies-JobAusgabe nicht gefunden — Aufbau geaendert?"
    } else {
        $texte = ([regex]::Matches($fnStill, "\`$T\['([a-zA-Z0-9_]+)'\]") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique |
                  ForEach-Object { "`$T['$_'] = '$_'" }) -join "`n"
        $stillblock = @'
param([string]$Fall)
$T = @{}
__TEXTE__
$LogFile = Join-Path ([System.IO.Path]::GetTempPath()) ("um-still-{0}.log" -f [guid]::NewGuid())
$Global:Config = $null
$script:Log = New-Object System.Collections.Generic.List[string]
$script:AllGerufen = 0; $script:Gemeldet = 0; $script:NachlaufMit = $null
$script:BenutzerIds = @(); $script:NachlaufErgebnis = @()
function Write-Log { param($m, $l = 'INFO')
    $script:Log.Add("$l|$m")
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$l] $m" -Encoding UTF8 }
function Test-AufgabeZeigtHierher { $true }
function Write-Anlauf { }
function Get-ZeitgrenzeHinweis { param($Ergebnis) '' }
function Test-WingetAvailable { $true }
function Test-ChocoAvailable { $true }
function Send-Meldung { $script:Gemeldet++; $false }
function Run-JobWithTimeout { param($ScriptBlock, $TimeoutSeconds) $script:Liste }
function Invoke-ProcessWithTimeout { param($FilePath, $ArgumentList, $TimeoutSeconds)
    if ($FilePath -like 'choco*') { return @{ TimedOut = $false; Output = @('Chocolatey upgraded 0/3 packages.'); ExitCode = 0 } }
    if ($ArgumentList -like 'upgrade --all*') { $script:AllGerufen++; return $script:All }
    return @{ TimedOut = $false; Output = @(); ExitCode = 0 } }
function Test-WingetBenutzerPaket { param($Id) $script:BenutzerIds -contains $Id }
function Update-BenutzerPakete { param($Ids) $script:NachlaufMit = @($Ids); return @($script:NachlaufErgebnis) }
__FUNKTIONEN__
$zeile = { param($n, $i) '{0,-7}{1,-11}{2,-8}{3,-10}{4}' -f $n, $i, '1.0', '1.1', 'winget' }
$tabelle = @(
    ('{0,-7}{1,-11}{2,-8}{3,-10}{4}' -f 'Name', 'ID', 'Version', 'Verfuegbar', 'Quelle'),
    ('-' * 45),
    (& $zeile 'Alpha' 'Test.Alpha'),
    (& $zeile 'Beta' 'Test.Beta'),
    '2 Aktualisierungen verfuegbar.')
$zwei = [pscustomobject]@{ Zustand = 'ok'; Ausgabe = $tabelle; Fehler = $null; Sekunden = 3 }
$script:All = @{ TimedOut = $false; ExitCode = -1978335188; Output = @(
    '(1/2) Gefunden Alpha [Test.Alpha] Version 1.1', 'Erfolgreich installiert',
    '(2/2) Gefunden Beta [Test.Beta] Version 1.1', 'Installation fehlgeschlagen') }
switch ($Fall) {
    'zeit'     { $script:Liste = [pscustomobject]@{ Zustand = 'zeit'; Ausgabe = $null; Fehler = $null; Sekunden = 60 } }
    'nichts'   { $script:Liste = [pscustomobject]@{ Zustand = 'ok'; Ausgabe = @('Es wurden keine installierten Pakete gefunden.'); Fehler = $null; Sekunden = 3 } }
    'benutzer' { $script:Liste = $zwei; $script:BenutzerIds = @('Test.Beta'); $script:NachlaufErgebnis = @('Test.Beta') }
    'rest'     { $script:Liste = $zwei; $script:BenutzerIds = @('Test.Beta'); $script:NachlaufErgebnis = @() }
    'maschine' { $script:Liste = $zwei }
}
try { Invoke-SilentUpdate 6>$null | Out-Null } finally { Remove-Item -LiteralPath $LogFile -ErrorAction SilentlyContinue }
[pscustomobject]@{
    Log = ($script:Log -join "`n"); AllGerufen = $script:AllGerufen
    Gemeldet = $script:Gemeldet; NachlaufMit = (@($script:NachlaufMit) -join ',')
} | ConvertTo-Json -Compress
'@
        $stillblock = $stillblock.Replace('__TEXTE__', $texte).Replace('__FUNKTIONEN__', $fnStill)
        $stilldatei = Join-Path ([System.IO.Path]::GetTempPath()) ("um-stillprobe-{0}.ps1" -f [guid]::NewGuid())
        [System.IO.File]::WriteAllText($stilldatei, $stillblock, (New-Object System.Text.UTF8Encoding $true))
        $laufe = {
            param($fall)
            $roh = & (Get-Process -Id $PID).Path -NoProfile -File $stilldatei -Fall $fall 2>&1
            $roh | Where-Object { "$_".TrimStart().StartsWith('{') } | Select-Object -Last 1 | ConvertFrom-Json
        }
        try {
            # Keine Liste: Fehler, kein "nichts offen", keine Erledigt-Marke.
            $z = & $laufe 'zeit'
            if ($z.Log -notmatch 'silent_no_updates' -or $z.Log -notmatch 'SUCCESS\|silent_winget_done') {
                if ($z.Log -match 'ERROR\|.*silent_winget_liste_fehlt') { Melde 'ok' "stiller Lauf: ohne winget-Liste steht ein Fehler da, kein 'Keine Updates'" }
                else { Schlecht "stiller Lauf: ohne winget-Liste fehlt der Fehler im Protokoll" }
            } else { Schlecht "stiller Lauf: winget-Abfrage lief in die Zeitgrenze und wird als 'Keine Updates' gemeldet" }
            if ($z.Log -notmatch '\[SILENT-DONE\]' -and $z.Log -match '\[SILENT-FAILED\]' -and $z.Gemeldet -eq 1) {
                Melde 'ok' "stiller Lauf: nach einem Fehler keine Erledigt-Marke, aber eine Meldung"
            } else { Schlecht "stiller Lauf: ein gescheiterter Lauf traegt [SILENT-DONE] oder meldet nicht — er wird nie nachgeholt" }

            # Wirklich nichts offen: gruen, Marke, keine Meldung.
            $n = & $laufe 'nichts'
            if ($n.Log -match 'SUCCESS\|silent_winget_done - silent_no_updates' -and $n.Log -match '\[SILENT-DONE\]' -and
                $n.Log -notmatch 'SILENT-FAILED' -and $n.Gemeldet -eq 0 -and $n.AllGerufen -eq 0 -and -not $n.NachlaufMit) {
                Melde 'ok' "stiller Lauf: nichts offen bleibt gruen, mit Erledigt-Marke und ohne Meldung"
            } else { Schlecht "stiller Lauf: ein Lauf ohne offene Updates wird nicht mehr sauber abgeschlossen: $($n.Log -replace "`n", ' / ')" }

            # Benutzer-Paket: wird nachgeholt, und nur dieses.
            $b = & $laufe 'benutzer'
            if ($b.NachlaufMit -eq 'Test.Beta' -and $b.Log -match 'SUCCESS\|silent_updated: Alpha, Beta' -and $b.Log -notmatch 'silent_winget_rest') {
                Melde 'ok' "stiller Lauf: Benutzer-Paket wird ohne erhoehte Rechte nachgeholt"
            } else { Schlecht "stiller Lauf: Benutzer-Paket wird nicht nachgeholt (Nachlauf mit '$($b.NachlaufMit)')" }

            # Nachlauf erfolglos: Der Rest wird genannt, der Lauf gilt trotzdem.
            $r = & $laufe 'rest'
            if ($r.Log -match 'WARNING\|silent_winget_rest: Beta' -and $r.Log -match 'SUCCESS\|silent_updated: Alpha \(') {
                Melde 'ok' "stiller Lauf: was nach einem Teilerfolg offen bleibt, steht als Warnung im Protokoll"
            } else { Schlecht "stiller Lauf: offene Pakete nach einem Teilerfolg werden still verworfen" }

            # Maschinen-Paket: KEIN Nachlauf (sonst UAC-Rueckfrage in der Nacht).
            $m = & $laufe 'maschine'
            if (-not $m.NachlaufMit -and $m.Log -match 'WARNING\|silent_winget_rest: Beta') {
                Melde 'ok' "stiller Lauf: Maschinen-Pakete gehen nicht in den Nachlauf"
            } elseif ($m.NachlaufMit) {
                Schlecht "stiller Lauf: ein Maschinen-Paket ging in den unerhoehten Nachlauf ('$($m.NachlaufMit)')"
            } else { Schlecht "stiller Lauf: ein offen gebliebenes Maschinen-Paket wird nicht genannt" }
        } catch {
            Schlecht "Probe des stillen Laufs liess sich nicht auswerten: $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $stilldatei -ErrorAction SilentlyContinue
        }
    }

    # Der Nachlauf sagt je Paket, ob es durchging.
    $fnErl = Hole-Funktion $Kern @('Get-NutzerlaufErledigt')
    if (-not $fnErl) {
        Schlecht "Get-NutzerlaufErledigt fehlt — der Nachlauf kann nicht sagen, was er erreicht hat"
    } else {
        $erl = & ([scriptblock]::Create($fnErl + "`n(Get-NutzerlaufErledigt -Zeilen `$args[0]) -join ','")) @(
            'Gefunden stripe [Test.Eins]', '##EXIT Test.Eins 0', '##EXIT Test.Zwei -1978335212', 'FERTIG')
        if ($erl -eq 'Test.Eins') { Melde 'ok' "Nachlauf: nur Pakete mit Exit 0 gelten als aktualisiert" }
        else { Schlecht "Nachlauf wertet die Exit-Zeilen falsch: '$erl'" }
    }
}

# ── 9c. Windows Update: nichts verschweigen, nichts ungefragt nachladen ─────
#
# Zwei Dinge vom 03.10.2026. Erstens zeigte der Manager ein grosses
# Windows-Update nicht an: Funktions- und Vorschau-Updates gibt Windows als
# OPTIONALE Installation frei, und die uebliche Suche findet sie nicht.
# Zweitens beantwortete sich die Frage "Modul PSWindowsUpdate nachladen?"
# aus dem Fenster heraus von selbst mit Ja.
#
# Gegen Attrappen: Die Suche beim Windows-Update-Dienst selbst laeuft hier
# nicht (sie braucht Netz und bis zu einer Minute).
if (Test-Path $Kern) {
    $fnWu = Hole-Funktion $Kern @('Write-WindowsWeitereUpdates', 'Select-WeitereUpdates')
    if (-not $fnWu) {
        Schlecht "Write-WindowsWeitereUpdates oder Select-WeitereUpdates fehlt — optionale Windows-Updates bleiben unsichtbar"
    } else {
        $wuVorspann = @'
$T = @{ wu_weitere = 'WEITERE'; wu_weitere_wo = 'wo'; wu_weitere_unbekannt = 'UNBEKANNT' }
$ColorInfo = 'Cyan'
$script:Gemeldet = @()
function Write-Log { param($m, $l) $script:Gemeldet += "$l|$m" }
function Search-WindowsUpdateTitel { param([switch]$Optional, [int]$TimeoutSeconds) $script:Antwort }
'@
        $wuFall = {
            param($antwort, $bekannt)
            $code = $wuVorspann + "`n" + $fnWu + "`n" +
                    '$script:Antwort = $args[0]' + "`n" +
                    'Write-WindowsWeitereUpdates -Bekannt $args[1] 6>$null' + "`n" +
                    '$script:Gemeldet -join " / "'
            & ([scriptblock]::Create($code)) $antwort $bekannt
        }
        $angebot = [pscustomobject]@{ Zustand = 'ok'; Fehler = $null; Ausgabe = @('Treiber A', 'Windows 11, version 99H9') }
        $neu = & $wuFall $angebot @('Treiber A')
        if ($neu -match 'WARNING\|WEITERE Windows 11, version 99H9' -and $neu -notmatch 'Treiber A') {
            Melde 'ok' "Windows Update: ein optionales Update, das die Liste nicht zeigt, wird als Warnung genannt"
        } else { Schlecht "Windows Update: optionales Update wird verschwiegen ('$neu')" }

        $still = & $wuFall $angebot @('Treiber A', 'Windows 11, version 99H9')
        if ([string]::IsNullOrWhiteSpace($still)) { Melde 'ok' "Windows Update: ist alles Angebotene schon in der Liste, bleibt es still" }
        else { Schlecht "Windows Update: warnt, obwohl nichts Weiteres ansteht ('$still')" }

        $blind = & $wuFall ([pscustomobject]@{ Zustand = 'zeit'; Fehler = $null; Ausgabe = $null }) @()
        if ($blind -match 'WARNING\|UNBEKANNT') { Melde 'ok' "Windows Update: laesst sich die Frage nicht klaeren, steht das da" }
        else { Schlecht "Windows Update: eine gescheiterte Suche nach optionalen Updates bleibt stumm ('$blind')" }
    }

    $fnTaste = Hole-Funktion $Kern @('Read-SingleKey')
    $kernText9c = Get-Content $Kern -Raw
    if (-not $fnTaste) {
        Schlecht "Read-SingleKey nicht gefunden — Aufbau geaendert?"
    } else {
        $taste = & ([scriptblock]::Create("`$ColorInfo = 'Cyan'; `$Global:OhneRueckfrage = `$true`n" + $fnTaste +
                 "`n(Read-SingleKey 'x' -Vorgabe 'n' 6>`$null) + (Read-SingleKey 'x' 6>`$null)`n`$Global:OhneRueckfrage = `$false"))
        $fragtNein = $kernText9c -match "Read-SingleKey\s+`"\`$\(\`$T\['wu_module_prompt'\]\)[^`r`n]*-Vorgabe\s+`"n`""
        if ($taste -eq 'nj' -and $fragtNein) {
            Melde 'ok' "PSWindowsUpdate wird ohne Tastatur nicht nachgeladen (Vorgabe nein), andere Fragen bleiben bei ja"
        } else {
            Schlecht "die Rueckfrage zum Nachladen von PSWindowsUpdate beantwortet sich ohne Tastatur mit Ja (Antworten: '$taste', Vorgabe gesetzt: $fragtNein)"
        }
    }
}

# ── 9d. Zeitgrenze: ganzer Prozessbaum, ehrliche Meldung ────────────────────
#
# `Process.Kill()` beendete nur den einen Prozess; ein Installer, den winget
# oder choco gestartet hatte, lief nach der "abgebrochenen" Zeitgrenze weiter.
# Hier laeuft ein echter kleiner Prozessbaum (PowerShell startet PowerShell,
# beide schlafen), und nach der Zeitgrenze darf keiner mehr da sein.
if (Test-Path $Kern) {
    $fnZeit = Hole-Funktion $Kern @('Invoke-ProcessWithTimeout', 'Stop-Prozessbaum')
    if (-not $fnZeit) {
        Schlecht "Invoke-ProcessWithTimeout oder Stop-Prozessbaum fehlt — nach einer Zeitgrenze bleiben Kindprozesse stehen"
    } else {
        $exeHier = (Get-Process -Id $PID).Path
        $pidDatei = Join-Path ([System.IO.Path]::GetTempPath()) ("um-kind-{0}.txt" -f [guid]::NewGuid())
        $eltern = "`$k = Start-Process -FilePath '$exeHier' -ArgumentList '-NoProfile','-Command','Start-Sleep 120' -PassThru -WindowStyle Hidden; " +
                  "Set-Content -LiteralPath '$pidDatei' -Value `$k.Id; Start-Sleep 120"
        $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($eltern))
        $kindPid = 0
        $zeitBeginn = Get-Date
        try {
            $lauf =[scriptblock]::Create($fnZeit + "`nInvoke-ProcessWithTimeout -FilePath `$args[0] -ArgumentList `$args[1] -TimeoutSeconds 12")
            $erg = & $lauf $exeHier "-NoProfile -EncodedCommand $kodiert"
            if (Test-Path $pidDatei) { $kindPid = [int](Get-Content -LiteralPath $pidDatei -Raw).Trim() }
            if (-not $erg.TimedOut) {
                Schlecht "Zeitgrenze: der schlafende Prozess wurde nicht als Zeitueberschreitung gemeldet"
            } elseif ($kindPid -le 0) {
                Melde '--' "Zeitgrenze: der Kindprozess kam nicht zustande — Prozessbaum nicht pruefbar"
            } else {
                Start-Sleep -Milliseconds 800
                $lebt = Get-Process -Id $kindPid -ErrorAction SilentlyContinue
                if (-not $lebt) { Melde 'ok' "Zeitgrenze: mit dem Prozess enden auch seine Kindprozesse" }
                else { Schlecht "Zeitgrenze: ein Kindprozess (PID $kindPid) lief nach dem Abbruch weiter" }
            }
            if ($erg.TimedOut -and $null -ne $erg.StartSeconds -and $null -ne $erg.CpuSeconds) {
                Melde 'ok' "Zeitgrenze: Startdauer und Rechenzeit werden mitgemessen ($($erg.StartSeconds) s, $($erg.CpuSeconds) s)"
            } else { Schlecht "Zeitgrenze: Startdauer oder Rechenzeit fehlt im Ergebnis" }
        } catch {
            Schlecht "Zeitgrenze liess sich nicht pruefen: $($_.Exception.Message)"
        } finally {
            # Aufraeumen, falls doch etwas uebrig ist: nur die EINE gemerkte
            # PID, und nur, wenn darunter noch UNSER Schlaefer laeuft (eine
            # PowerShell, gestartet nach Beginn dieser Pruefung). Windows
            # vergibt PIDs neu; ohne den Blick trifft es sonst einen Fremden.
            if ($kindPid -gt 0) {
                $rest = Get-Process -Id $kindPid -ErrorAction SilentlyContinue
                if ($rest -and $rest.ProcessName -match '^(pwsh|powershell)$' -and $rest.StartTime -ge $zeitBeginn) {
                    Stop-Process -Id $kindPid -Force -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -LiteralPath $pidDatei -ErrorAction SilentlyContinue
        }
    }

    $fnHinweis = Hole-Funktion $Kern @('Get-ZeitgrenzeHinweis', 'Test-AnlaufLang', 'Test-PrioritaetNiedrig')
    if (-not $fnHinweis) {
        Schlecht "Get-ZeitgrenzeHinweis, Test-AnlaufLang oder Test-PrioritaetNiedrig fehlt"
    } else {
        $h = & ([scriptblock]::Create(
            "`$T = @{ zeit_start = 'START'; zeit_rechenzeit = 'CPU'; zeit_ausgelastet = 'AUSGELASTET' }`n" + $fnHinweis + "`n" +
            "[pscustomobject]@{`n" +
            "  Traege = Get-ZeitgrenzeHinweis @{ StartSeconds = 58.0; CpuSeconds = 0.4 }`n" +
            "  Flink  = Get-ZeitgrenzeHinweis @{ StartSeconds = 0.2; CpuSeconds = 41.0 }`n" +
            "  Anlauf = '' + (Test-AnlaufLang 420) + (Test-AnlaufLang 3) + (Test-AnlaufLang `$null)`n" +
            "  Prio   = '' + (Test-PrioritaetNiedrig 7) + (Test-PrioritaetNiedrig 4) + (Test-PrioritaetNiedrig `$null)`n" +
            "}"))
        if ($h.Traege -match 'AUSGELASTET' -and $h.Traege -match 'START 58' -and $h.Flink -notmatch 'AUSGELASTET' -and $h.Flink -match 'CPU 41') {
            Melde 'ok' "Zeitgrenze: 'ausgelastet' steht nur da, wenn schon der Start lange dauerte"
        } else { Schlecht "Zeitgrenze: der Hinweis stimmt nicht ('$($h.Traege)' / '$($h.Flink)')" }
        if ($h.Anlauf -eq 'TrueFalseFalse' -and $h.Prio -eq 'TrueFalseFalse') {
            Melde 'ok' "langer Anlauf und niedrige Prioritaet werden erkannt, der Normalfall nicht"
        } else { Schlecht "Anlauf oder Prioritaet falsch bewertet (Anlauf $($h.Anlauf), Prioritaet $($h.Prio))" }
    }

    if ((Get-Content $Kern -Raw) -match 'New-ScheduledTaskSettingsSet[^\r\n]*-Priority 4') {
        Melde 'ok' "die geplante Aufgabe wird mit normaler Prioritaet (4) eingetragen"
    } else {
        Schlecht "die geplante Aufgabe wird ohne Prioritaet eingetragen — die Vorgabe ist 7 (niedrig)"
    }
}

# ── 9e. Das Protokoll haelt sieben Tage ─────────────────────────────────────
#
# Zwei Rotationen nach Groesse lagen nebeneinander (5 MB und 1 MB), und die
# Sicherung vom Umkodieren blieb fuer immer liegen. Jetzt gilt eine Frist.
# Geprueft wird in einem eigenen Ordner mit festem "Jetzt": Was aelter ist,
# faellt weg — und was juenger ist, bleibt Byte fuer Byte, wie es war.
if (Test-Path $Kern) {
    $fnLog = Hole-Funktion $Kern @('Invoke-LogPflege')
    $kernText9e = Get-Content $Kern -Raw
    if (-not $fnLog) {
        Schlecht "Invoke-LogPflege fehlt — das Protokoll wird nicht nach Zeit gehalten"
    } else {
        $logOrdner = Join-Path ([System.IO.Path]::GetTempPath()) ("um-logprobe-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $logOrdner -Force | Out-Null
        $jetzt = [datetime]'2026-10-03T12:00:00'
        $pflege = [scriptblock]::Create(
            "`$T = @{ log_gekuerzt = 'GEKUERZT'; log_tage = 'Tage'; log_altdatei = 'ALTDATEI'; log_pflege_fehler = 'PFLEGEFEHLER' }`n" +
            "`$script:Gemeldet = @()`nfunction Write-Log { param(`$m, `$l) `$script:Gemeldet += `"`$l|`$m`" }`n" + $fnLog +
            "`nInvoke-LogPflege -Pfad `$args[0] -Tage 7 -Jetzt `$args[1]`n`$script:Gemeldet -join ' / '")
        $angelegt = @()
        try {
            # Fall A: Altes faellt weg, Junges bleibt.
            $logA = Join-Path $logOrdner 'universal-update-manager.log'
            [System.IO.File]::WriteAllLines($logA, [string[]]@(
                '[2026-09-20 04:00:00] [INFO] uralt',
                '   Fortsetzung der uralten Zeile ohne Zeitstempel',
                '[2026-09-26 11:59:59] [ERROR] eine Sekunde zu alt',
                '[2026-09-26 12:00:00] [INFO] genau sieben Tage',
                '   Fortsetzung, die bleiben muss',
                '[2026-10-03 04:00:00] [INFO] heute, mit Umlaut ü'
            ), (New-Object System.Text.UTF8Encoding $true))
            $alteNeben = @("$logA.ansi-sicherung", "$logA.1", (Join-Path $logOrdner 'universal-update-manager_20260901_040000.log'))
            foreach ($d in $alteNeben) { Set-Content -LiteralPath $d -Value 'alt'; (Get-Item -LiteralPath $d).LastWriteTime = $jetzt.AddDays(-12) }
            $fremd = Join-Path $logOrdner 'anderes-werkzeug.log'
            Set-Content -LiteralPath $fremd -Value 'gehoert nicht dazu'; (Get-Item -LiteralPath $fremd).LastWriteTime = $jetzt.AddDays(-90)
            $angelegt += $logA; $angelegt += $alteNeben; $angelegt += $fremd; $angelegt += "$logA.neu"

            $meldA = & $pflege $logA $jetzt
            $nachA = [System.IO.File]::ReadAllLines($logA, [System.Text.Encoding]::UTF8)
            $sollA = @('[2026-09-26 12:00:00] [INFO] genau sieben Tage', '   Fortsetzung, die bleiben muss', '[2026-10-03 04:00:00] [INFO] heute, mit Umlaut ü')
            if (($nachA -join '|') -eq ($sollA -join '|') -and $meldA -match 'GEKUERZT: 3') {
                Melde 'ok' "Protokoll: Zeilen aelter als 7 Tage fallen weg, samt ihren Fortsetzungszeilen"
            } else { Schlecht "Protokoll: nach der Pflege stehen die falschen Zeilen da: $($nachA -join ' | ') [$meldA]" }
            $nochDa = @($alteNeben | Where-Object { Test-Path -LiteralPath $_ })
            if ($nochDa.Count -eq 0 -and (Test-Path -LiteralPath $fremd)) {
                Melde 'ok' "Protokoll: .ansi-sicherung, .1 und datierte Archive gehen nach 7 Tagen, fremde Dateien bleiben"
            } else { Schlecht "Protokoll: Altdateien bleiben liegen oder Fremdes wurde entfernt (noch da: $($nochDa.Count), fremde Datei da: $(Test-Path -LiteralPath $fremd))" }

            # Fall B: Nichts ist alt — nichts wird angefasst.
            $logB = Join-Path $logOrdner 'frisch.log'
            [System.IO.File]::WriteAllLines($logB, [string[]]@(
                '[2026-09-30 04:00:00] [INFO] drei Tage alt',
                '[2026-10-03 04:00:00] [INFO] heute'
            ), (New-Object System.Text.UTF8Encoding $false))
            Set-Content -LiteralPath "$logB.ansi-sicherung" -Value 'jung'; (Get-Item -LiteralPath "$logB.ansi-sicherung").LastWriteTime = $jetzt.AddDays(-2)
            $angelegt += $logB; $angelegt += "$logB.ansi-sicherung"; $angelegt += "$logB.neu"
            $vorB = [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($logB))
            $meldB = & $pflege $logB $jetzt
            $nachB = [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($logB))
            if ($vorB -eq $nachB -and [string]::IsNullOrWhiteSpace($meldB) -and (Test-Path -LiteralPath "$logB.ansi-sicherung")) {
                Melde 'ok' "Protokoll: ist nichts aelter als 7 Tage, bleibt alles unberuehrt (auch eine junge Sicherung)"
            } else { Schlecht "Protokoll: ein frisches Protokoll wurde veraendert oder eine junge Sicherung entfernt [$meldB]" }

            # Fall C: Unter dem Namen der Zwischendatei liegt schon etwas, das
            # keine gewoehnliche Datei ist (hier ein Ordner; ein Link waere
            # derselbe Zweig). Der erhoehte Lauf schreibt dann NICHT hinein,
            # sagt es, und das Protokoll bleibt, wie es war.
            $logC = Join-Path $logOrdner 'belegt.log'
            [System.IO.File]::WriteAllLines($logC, [string[]]@(
                '[2026-09-01 04:00:00] [INFO] alt',
                '[2026-10-03 04:00:00] [INFO] heute'
            ), (New-Object System.Text.UTF8Encoding $true))
            New-Item -ItemType Directory -Path "$logC.neu" -Force | Out-Null
            $angelegt += $logC; $angelegt += "$logC.neu"
            $vorC = [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($logC))
            $meldC = & $pflege $logC $jetzt
            $nachC = [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($logC))
            if ($vorC -eq $nachC -and $meldC -match 'WARNING\|PFLEGEFEHLER' -and (Test-Path -LiteralPath "$logC.neu" -PathType Container)) {
                Melde 'ok' "Protokoll: liegt unter dem Namen der Zwischendatei ein Ordner oder Link, wird nichts ueberschrieben und es steht da"
            } else { Schlecht "Protokoll: eine belegte Zwischendatei wird ueberschrieben oder verschwiegen [$meldC]" }
        } catch {
            Schlecht "Protokollpflege liess sich nicht pruefen: $($_.Exception.Message)"
        } finally {
            foreach ($d in $angelegt) { Remove-Item -LiteralPath $d -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $logOrdner -ErrorAction SilentlyContinue
        }
    }
    if ($kernText9e -notmatch 'MaxLogSizeMB' -and $kernText9e -notmatch 'function Invoke-LogUmbruch') {
        Melde 'ok' "es gibt nur noch eine Protokollpflege (die beiden Rotationen nach Groesse sind weg)"
    } else {
        Schlecht "eine der alten Rotationen nach Groesse steht noch im Kern — zwei Regeln fuer ein Protokoll"
    }
}

# ── 9b. Protokoll-Ansicht: neueste Laeufe oben ──────────────────────────────
# Die Datei bleibt chronologisch (Leser wie der Tagesmarker des stillen Laufs
# setzen das voraus); angezeigt wird eine Kopie mit umgekehrten LAEUFEN.
# Innerhalb eines Laufs bleibt die Reihenfolge, der Laeufe-Wechsel wird am
# Dreiklang "====", Titel, "====" erkannt.
if (Test-Path $Kern) {
    $fnAnsicht = Hole-Funktion $Kern @('Get-ProtokollNeuestZuerst')
    if (-not $fnAnsicht) {
        Schlecht "Get-ProtokollNeuestZuerst fehlt - das Protokoll laesst sich nicht neueste-zuerst zeigen"
    } else {
        $tr = '[2026-10-08 01:00:00] [INFO] ========================================'
        $eingabe = @('[x] [GUI] [ERROR] vorab', $tr, '[t] [INFO] Start A', $tr, '[t] [INFO] a1', '   Fortsetzung a1', $tr,
                     $tr, '[t] [INFO] Start B', $tr, '[t] [INFO] b1', '[t] [INFO] b2', $tr, '[t] [INFO] [SILENT-DONE] fertig', $tr)
        $ordnung = & ([scriptblock]::Create($fnAnsicht + "`nGet-ProtokollNeuestZuerst -Zeilen `$args[0]")) $eingabe
        $namen = @($ordnung | Where-Object { $_ -match 'Start|a1|b1|vorab|Fortsetzung|SILENT|b2' } | ForEach-Object { ($_ -replace '^\[[^\]]*\] (\[[A-Za-z]+\] )?', '').Trim() })
        $soll = 'Start B|b1|b2|[SILENT-DONE] fertig|Start A|a1|Fortsetzung a1|[ERROR] vorab'
        if (($namen -join '|') -eq $soll -and @($ordnung).Count -eq $eingabe.Count) {
            Melde 'ok' "Protokoll-Ansicht: neueste Laeufe oben, innerhalb eines Laufs in Reihenfolge, nichts geht verloren"
        } else { Schlecht "Protokoll-Ansicht: falsche Reihenfolge: $($namen -join '|')" }
    }
}

# ── 11. Selbst-Update (SELBST-UPDATE.md) ────────────────────────────────────
#
# Alles gegen gespeicherte Antworten und Attrappen: kein Netz, kein echtes
# Setup. Bei AUS (Vorgabe) ist die Probe gruen, wenn das Fenster nichts
# installieren kann, solange der Schalter nicht gesetzt ist.
$SelbstUpdate = Join-Path $Ordner 'selbst-update.ps1'
if (-not (Test-Path $SelbstUpdate)) {
    Schlecht "selbst-update.ps1 fehlt"
} else {
    $f = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($SelbstUpdate, [ref]$null, [ref]$f)
    $kopf = [System.IO.File]::ReadAllBytes($SelbstUpdate) | Select-Object -First 3
    if ($f -and $f.Count -gt 0) { Schlecht "selbst-update.ps1 hat Syntaxfehler: $($f[0].Message)" }
    elseif (-not ($kopf.Count -ge 3 -and $kopf[0] -eq 0xEF -and $kopf[1] -eq 0xBB -and $kopf[2] -eq 0xBF)) { Schlecht "selbst-update.ps1 hat KEIN BOM" }
    else { Melde 'ok' "selbst-update.ps1 laesst sich parsen, mit BOM" }

    $iss = Join-Path $Ordner 'installer\update-manager.iss'
    if ((Test-Path $iss) -and ((Get-Content $iss -Raw) -notmatch 'selbst-update\.ps1')) {
        Schlecht "installer\update-manager.iss nimmt selbst-update.ps1 nicht mit - das Fenster zeigte nach dem Setup keine neue Fassung"
    }

    # Die Funktionen in einem Kindbereich laden (nichts leckt in die Probe).
    $ergebnisse = & {
        . $SelbstUpdate
        $r = New-Object System.Collections.Generic.List[string]
        function Pruefe($ok, $text) { if (-not $ok) { $r.Add($text) } }

        # Versionsvergleich als Zahl, nicht als Text.
        Pruefe (Test-FassungNeuer 'v3.10.0' '3.9.0') '3.10.0 muss neuer sein als 3.9.0'
        Pruefe (-not (Test-FassungNeuer 'v3.2.0' '3.2.0')) 'gleiche Version ist nicht neuer'
        Pruefe (-not (Test-FassungNeuer 'v3.1.9' '3.2.0')) 'aeltere Version ist nicht neuer'
        Pruefe (Test-FassungNeuer 'v3.3.0-rc1' '3.2.0') 'Vorabteil hinter - wird abgeschnitten'
        Pruefe (-not (Test-FassungNeuer 'abc' '3.2.0')) 'Unsinn ist nicht neuer'
        Pruefe (-not (Test-FassungNeuer '' '3.2.0')) 'leeres Tag ist nicht neuer'

        # Adresspruefung: fester Anfang.
        $gut = 'https://github.com/MelucioLabs/update-manager/releases/download/v3.3.0/MelucioLabs-Update-Manager-Setup-3.3.0.exe'
        Pruefe (Test-SelbstUpdateAdresse $gut) 'die richtige Adresse wird abgelehnt'
        foreach ($schlecht in @(
            'http://github.com/MelucioLabs/update-manager/releases/download/v3.3.0/a.exe',
            'https://github.com/Fremd/update-manager/releases/download/v3.3.0/a.exe',
            'https://github.com.evil.example/MelucioLabs/update-manager/releases/download/v1/a.exe',
            'https://github.com/MelucioLabs/update-manager/releases/download/../../x/a.exe',
            'https://github.com/MelucioLabs/update-manager/releases/download/v1/a.exe@evil.example',
            '', $null)) {
            Pruefe (-not (Test-SelbstUpdateAdresse $schlecht)) "Adresse ohne Pruefung durchgelassen: $schlecht"
        }

        # Pruefsummenliste.
        $h = ('ab' * 32)
        $liste = "$h  MelucioLabs-Update-Manager-Setup-3.3.0.exe`r`n" + ('cd' * 32) + "  update-manager.sh`r`n"
        Pruefe ((Lies-Pruefsumme $liste 'MelucioLabs-Update-Manager-Setup-3.3.0.exe') -eq $h) 'Pruefsumme nicht gefunden'
        Pruefe ($null -eq (Lies-Pruefsumme $liste 'andere.exe')) 'Pruefsumme fuer fremden Namen geliefert'
        Pruefe ($null -eq (Lies-Pruefsumme 'kaputt' 'x.exe')) 'kaputte Liste liefert eine Summe'

        # Waehle-Fassung gegen gespeicherte Antworten.
        function Antwort($tag, $draft, $pre, $setupUrl, $name) {
            $json = @{
                tag_name = $tag; draft = $draft; prerelease = $pre
                html_url = "https://github.com/MelucioLabs/update-manager/releases/tag/$tag"
                assets = @(
                    @{ name = $name; browser_download_url = $setupUrl },
                    @{ name = 'SHA256SUMS.txt'; browser_download_url = 'https://github.com/MelucioLabs/update-manager/releases/download/v3.3.0/SHA256SUMS.txt' }
                )
            } | ConvertTo-Json -Depth 5
            $json | ConvertFrom-Json
        }
        $n = 'MelucioLabs-Update-Manager-Setup-3.3.0.exe'
        $a1 = Waehle-Fassung (Antwort 'v3.3.0' $false $false $gut $n)
        Pruefe ($a1 -and $a1.SetupName -eq $n -and $a1.Version -eq [version]'3.3.0') 'gueltige Antwort wird nicht erkannt'
        Pruefe ($null -eq (Waehle-Fassung (Antwort 'v3.3.0' $true $false $gut $n))) 'Entwurf wird angeboten'
        Pruefe ($null -eq (Waehle-Fassung (Antwort 'v3.3.0' $false $true $gut $n))) 'Vorabfassung wird angeboten'
        Pruefe ($null -eq (Waehle-Fassung (Antwort 'v3.3.0' $false $false 'https://evil.example/a.exe' $n))) 'fremde Adresse wird angeboten'
        Pruefe ($null -eq (Waehle-Fassung (Antwort 'v3.3.0' $false $false $gut 'anderer-name.exe'))) 'Setup mit falschem Namen wird angeboten'
        Pruefe ($null -eq (Waehle-Fassung $null)) 'keine Antwort ergibt etwas'
        # Downgrade-Mischung: hohes Tag, Dateien eines alten Releases.
        $alt310 = 'https://github.com/MelucioLabs/update-manager/releases/download/v3.1.0/MelucioLabs-Update-Manager-Setup-3.1.0.exe'
        Pruefe ($null -eq (Waehle-Fassung (Antwort 'v3.3.0' $false $false $alt310 $n))) 'Setup eines anderen Release-Tags wird angeboten'
        $kaputt = [pscustomobject]@{ fassung = 'nur ein Text' }
        Pruefe ($null -eq (Lies-GemerkteFassung $kaputt)) 'unvollstaendige gemerkte Fassung wirft oder wird geglaubt'
        Pruefe ($null -eq (Lies-GemerkteFassung ([pscustomobject]@{ fassung = [pscustomobject]@{ tag = 'v9.9.9' } }))) 'gemerkte Fassung ohne Felder wird geglaubt'

        # Zustand: hoechstens einmal am Tag, gemerkte Fassung wird neu geprueft.
        $jetzt = [datetime]::UtcNow
        Pruefe (-not (Test-HeuteSchonGefragt $null $jetzt)) 'ohne Zustand gilt als nicht gefragt'
        Pruefe (Test-HeuteSchonGefragt ([pscustomobject]@{ geprueft = $jetzt.AddHours(-3).ToString('o') }) $jetzt) 'vor 3 Stunden gefragt wird nicht erkannt'
        Pruefe (-not (Test-HeuteSchonGefragt ([pscustomobject]@{ geprueft = $jetzt.AddHours(-25).ToString('o') }) $jetzt)) 'vor 25 Stunden gefragt zaehlt noch als heute'
        Pruefe (-not (Test-HeuteSchonGefragt ([pscustomobject]@{ geprueft = $jetzt.AddHours(5).ToString('o') }) $jetzt)) 'Zeitpunkt in der Zukunft wird geglaubt'
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("um-probe-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $zp = Join-Path $tmp 'selbst-update.json'
            Schreibe-SelbstUpdateZustand $zp $a1 ''
            $g = Lies-GemerkteFassung (Lies-SelbstUpdateZustand $zp)
            Pruefe ($g -and $g.Tag -eq 'v3.3.0' -and $g.SetupUrl -eq $gut) 'gemerkte Fassung kommt nicht heil zurueck'
            $text = Get-Content $zp -Raw
            Set-Content -LiteralPath $zp -Value ($text -replace 'github\.com/MelucioLabs', 'evil.example/MelucioLabs') -Encoding UTF8
            Pruefe ($null -eq (Lies-GemerkteFassung (Lies-SelbstUpdateZustand $zp))) 'veraenderte gemerkte Adresse wird geglaubt'

            # Schalter: Vorgabe aus dem Repo und Ueberschreiben.
            $s0 = Lies-SelbstUpdateSchalter $tmp
            Pruefe ($s0.Pruefen -eq $true -and $s0.Installieren -eq $false) 'ohne Konfiguration muss Pruefen an und Installieren AUS sein'
            Set-Content -LiteralPath (Join-Path $tmp 'update-config.local.json') -Value '{"selbstUpdate":{"installieren":true}}' -Encoding UTF8
            Pruefe ((Lies-SelbstUpdateSchalter $tmp).Installieren -eq $true) 'eigener Schalter installieren=true greift nicht'
            Set-Content -LiteralPath (Join-Path $tmp 'update-config.local.json') -Value '{kaputt' -Encoding UTF8
            Pruefe ((Lies-SelbstUpdateSchalter $tmp).Installieren -eq $false) 'kaputte Konfiguration muss bei AUS bleiben'

            # Installieren gegen eine Attrappe (whoami.exe als "Setup").
            $echt = Join-Path $env:SystemRoot 'System32\whoami.exe'
            if (Test-Path $echt) {
                $fake = Join-Path $tmp 'Setup.exe'
                Copy-Item $echt $fake
                $summe = (Get-FileHash -LiteralPath $fake -Algorithm SHA256).Hash.ToLower()
                $x = Installiere-Setup -Pfad $fake -ErwarteteSumme ('0' * 64) -UnsigniertErlaubt -Argumente @('/?')
                Pruefe (-not $x.Gestartet) 'falsche Pruefsumme darf nichts starten'
                $x = Installiere-Setup -Pfad $fake -ErwarteteSumme 'zzz' -UnsigniertErlaubt -Argumente @('/?')
                Pruefe (-not $x.Gestartet) 'ungueltige Pruefsumme darf nichts starten'
                $x = Installiere-Setup -Pfad $fake -ErwarteteSumme $summe -Argumente @('/?')
                Pruefe (-not $x.Gestartet) 'unsigniertes Setup ohne Bestaetigung darf nichts starten'
                $x = Installiere-Setup -Pfad $fake -ErwarteteSumme $summe -UnsigniertErlaubt -Argumente @('/?')
                Pruefe ($x.Gestartet -and $x.ExitCode -eq 0) "bestaetigtes Setup mit richtiger Summe wird nicht gestartet: $($x.Meldung)"
                # Sobald ein Aussteller hinterlegt ist, hilft die Bestaetigung nicht mehr.
                $script:SU_SignaturAussteller = 'MelucioLabs'
                $x = Installiere-Setup -Pfad $fake -ErwarteteSumme $summe -UnsigniertErlaubt -Argumente @('/?')
                Pruefe (-not $x.Gestartet) 'mit hinterlegtem Aussteller darf ein unsigniertes Setup nie starten'
                $script:SU_SignaturAussteller = ''
            }
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        , $r
    }
    $liste = @($ergebnisse | ForEach-Object { $_ })
    if ($liste.Count -eq 0) { Melde 'ok' "Selbst-Update: Versionsvergleich, Adresspruefung, Antwortauswahl, Tagesgrenze, Schalter (Vorgabe AUS) und Setup-Pruefung bestehen" }
    else { foreach ($l in $liste) { Schlecht "Selbst-Update: $l" } }

    # Die Vorgabe im Repo: Installieren AUS, solange nicht signiert.
    try {
        $vorgabe = (Get-Content $Konfig -Raw | ConvertFrom-Json).selbstUpdate
        if ($vorgabe -and $vorgabe.installieren -eq $false) { Melde 'ok' "update-config.json: selbstUpdate.installieren steht auf false (Vorgabe AUS)" }
        else { Schlecht "update-config.json: selbstUpdate.installieren muss false sein, bis das Setup signiert ist" }
    } catch { Schlecht "update-config.json: selbstUpdate nicht lesbar" }
}

# ── 12. Protokoll-Ansicht und Ergebniskarte (protokoll-ansicht.ps1) ─────────
#
# Die Datei universal-update-manager.log bleibt chronologischer Text; die
# Ansicht im Fenster ordnet nur um. Geprueft wird mit Text, nicht mit einer
# echten Protokolldatei.
$Ansicht = Join-Path $Ordner 'protokoll-ansicht.ps1'
if (-not (Test-Path $Ansicht)) {
    Schlecht "protokoll-ansicht.ps1 fehlt"
} else {
    $f = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Ansicht, [ref]$null, [ref]$f)
    $kopf = [System.IO.File]::ReadAllBytes($Ansicht) | Select-Object -First 3
    if ($f -and $f.Count -gt 0) { Schlecht "protokoll-ansicht.ps1 hat Syntaxfehler: $($f[0].Message)" }
    elseif (-not ($kopf.Count -ge 3 -and $kopf[0] -eq 0xEF -and $kopf[1] -eq 0xBB -and $kopf[2] -eq 0xBF)) { Schlecht "protokoll-ansicht.ps1 hat KEIN BOM" }
    else { Melde 'ok' "protokoll-ansicht.ps1 laesst sich parsen, mit BOM" }

    $iss2 = Join-Path $Ordner 'installer\update-manager.iss'
    if ((Test-Path $iss2) -and ((Get-Content $iss2 -Raw) -notmatch 'protokoll-ansicht\.ps1')) {
        Schlecht "installer\update-manager.iss nimmt protokoll-ansicht.ps1 nicht mit - das Protokoll bliebe nach dem Setup unformatiert"
    }

    $ergebnisse2 = & {
        . $Ansicht
        $r = New-Object System.Collections.Generic.List[string]
        function Pruefe($ok, $text) { if (-not $ok) { $r.Add($text) } }

        $zeilen = @(
            '[2026-10-07 04:00:01] [INFO] ========================================',
            '[2026-10-07 04:00:01] [INFO] Silent Mode gestartet',
            '[2026-10-07 04:00:02] [ERROR] Winget Zeit ueberschritten',
            '   Fortsetzung der Fehlerzeile',
            '[2026-10-07 04:05:00] [INFO] [SILENT-FAILED] Lauf nicht beendet',
            '[2026-10-08 04:00:01] [INFO] ========================================',
            '[2026-10-08 04:00:01] [INFO] Silent Mode gestartet',
            '[2026-10-08 04:01:00] [WARNING] Rest offen: D',
            '[2026-10-08 04:02:00] [SUCCESS] Aktualisiert: A, B (2 Updates)',
            '[2026-10-08 04:02:30] [SUCCESS] Aktualisiert: C (1 Updates)',
            '[2026-10-08 04:03:00] [GUI] [ERROR] Fenster meldet etwas',
            '[2026-10-08 04:03:10] [INFO] [SILENT-DONE] Silent Mode beendet',
            ''
        )
        $e = ConvertTo-ProtokollEintraege $zeilen
        Pruefe (@($e).Count -eq 9) "Eintraege: $(@($e).Count) statt 9 (Trenner und Leerzeilen fallen weg, Fortsetzung haengt an)"
        Pruefe ($e[1].Text -like "*Zeit ueberschritten*Fortsetzung der Fehlerzeile*") 'Fortsetzungszeile haengt nicht an der Zeile davor'
        $gui = @($e | Where-Object { $_.Text -like 'Fenster meldet*' })[0]
        Pruefe ($gui -and $gui.Stufe -eq 'ERROR') '[GUI] [ERROR]: die Stufe wird nicht erkannt'
        $done = @($e | Where-Object { $_.Text -like '*SILENT-DONE*' })[0]
        Pruefe ($done -and $done.Stufe -eq 'INFO') '[INFO] [SILENT-DONE]: Marke geht verloren'

        $tage = Gruppiere-ProtokollTage $e
        Pruefe (@($tage).Count -eq 2 -and $tage[0].Datum -eq '2026-10-08') 'neuester Tag steht nicht oben'
        Pruefe ($tage[0].Eintraege[0].Zeit -eq '04:00' -and $tage[0].Eintraege[-1].Zeit -eq '04:03') 'Zeilen eines Tages nicht in zeitlicher Reihenfolge'
        $nurF = Gruppiere-ProtokollTage $e -NurFehler
        $anzF = (@($nurF | ForEach-Object { $_.Eintraege }) | Measure-Object).Count
        Pruefe ($anzF -eq 2) "Filter Fehler liefert $anzF statt 2"
        $z = Get-ProtokollZaehler $e
        Pruefe ($z.Fehler -eq 2 -and $z.Warnungen -eq 1) "Zaehler: $($z.Fehler) Fehler, $($z.Warnungen) Warnungen"

        Pruefe ((Get-LaufAnzahl $e) -eq 2) "Laufzaehler: $(Get-LaufAnzahl $e) statt 2 (ein FAILED, ein DONE)"
        Pruefe ((Get-LaufAnzahl @()) -eq 0) 'Laufzaehler ohne Eintraege muss 0 sein'
        $heute = [datetime]'2026-10-08 12:00'
        Pruefe ((Get-TagesKopf '2026-10-08' $heute) -eq 'Heute, 8. Oktober 2026') "Tageskopf heute: $(Get-TagesKopf '2026-10-08' $heute)"
        Pruefe ((Get-TagesKopf '2026-10-07' $heute) -eq 'Gestern, 7. Oktober 2026') 'Tageskopf gestern'
        Pruefe ((Get-TagesKopf '2026-10-05' $heute) -like 'Montag, 5. Oktober 2026') "Tageskopf Wochentag: $(Get-TagesKopf '2026-10-05' $heute)"

        # Ergebniskarte: die Faelle aus dem Entwurf.
        $lauf = Get-LetzterLauf $e
        $k = Bilde-ErgebnisKarte $lauf
        Pruefe ($lauf.Anzahl -eq 3 -and $lauf.Fehler -eq 1) "Letzter Lauf: $($lauf.Anzahl) Updates, $($lauf.Fehler) Fehler (erwartet 3 und 1)"
        Pruefe ($k.Ton -eq 'warn' -and $k.Zahl -eq '3') "3 Updates mit Fehler muss gelb sein, ist $($k.Ton)"
        $k = Bilde-ErgebnisKarte @{ Gefunden = $true; Gescheitert = $false; Fehler = 0; Anzahl = 5 }
        Pruefe ($k.Ton -eq 'gut' -and $k.Satz -eq 'Es gab 5 Updates, alle erfolgreich installiert.') "5 Updates ohne Fehler: $($k.Satz)"
        $k = Bilde-ErgebnisKarte @{ Gefunden = $true; Gescheitert = $false; Fehler = 0; Anzahl = 1 }
        Pruefe ($k.Satz -eq 'Es gab 1 Update, erfolgreich installiert.') "1 Update: $($k.Satz)"
        $k = Bilde-ErgebnisKarte @{ Gefunden = $true; Gescheitert = $true; Fehler = 2; Anzahl = 0 }
        Pruefe ($k.Ton -eq 'schlecht') 'gescheiterter Lauf muss rot sein'
        $k = Bilde-ErgebnisKarte @{ Gefunden = $true; Gescheitert = $false; Fehler = 0; Anzahl = 0 }
        Pruefe ($k.Ton -eq 'neutral' -and $k.Satz -like 'Alles aktuell*') 'nichts zu tun muss grau und "Alles aktuell" sein'
        $k = Bilde-ErgebnisKarte @{ Gefunden = $false; Gescheitert = $false; Fehler = 0; Anzahl = 0 }
        Pruefe ($k.Ton -eq 'neutral') 'ohne Lauf im Protokoll muss die Karte grau sein'
        Pruefe ((Get-LetzterLauf (ConvertTo-ProtokollEintraege @('[2026-10-08 04:00:01] [INFO] nichts'))).Gefunden -eq $false) 'Lauf ohne Marke wird als letzter Lauf gelesen'
        , $r
    }
    $liste2 = @($ergebnisse2 | ForEach-Object { $_ })
    if ($liste2.Count -eq 0) { Melde 'ok' "Protokoll-Ansicht: Eintraege, Tage neueste zuerst, Fehlerfilter, Tageskopf und Ergebniskarte (gruen, gelb, rot, grau) stimmen" }
    else { foreach ($l in $liste2) { Schlecht "Protokoll-Ansicht: $l" } }
}

# ── 10. Konfiguration ───────────────────────────────────────────────────────
if (-not (Test-Path $Konfig)) {
    Schlecht "update-config.json fehlt"
} else {
    try {
        $k = Get-Content $Konfig -Raw | ConvertFrom-Json
        $noetig = @('updateSources')
        $fehlt = $noetig | Where-Object { -not ($k.PSObject.Properties.Name -contains $_) }
        if ($fehlt) { Schlecht "update-config.json fehlt der Abschnitt: $($fehlt -join ', ')" }
        else { Melde 'ok' "update-config.json ist lesbar und vollstaendig" }
    } catch {
        Schlecht "update-config.json laesst sich nicht lesen: $($_.Exception.Message)"
    }
}

Write-Host ""
if ($Fehler.Count -eq 0) {
    Write-Host "Alles gruen ($($Zeilen.Count) Pruefungen)." -ForegroundColor Green
    exit 0
}
Write-Host "$($Fehler.Count) Fund(e):" -ForegroundColor Red
foreach ($f in $Fehler) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
