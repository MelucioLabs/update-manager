# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Protokoll-Ansicht des Fensters (Stand 08.10.2026).

    NUR FUNKTIONEN, rein und ohne Dateizugriff: Sie nehmen Zeilen und liefern
    Daten. update-manager-gui.ps1 laedt die Datei und baut daraus die Anzeige;
    probe.ps1 fuettert sie mit Text.

    Die Datei universal-update-manager.log BLEIBT chronologischer Text. Die
    Tagesmarke [SILENT-DONE] und die Kuerzung auf sieben Tage lesen sie so.
    Hier wird nur die ANZEIGE umgestellt: neueste Tage oben, innerhalb eines
    Tages in zeitlicher Reihenfolge.

    Zeilenformat (Write-Log im Kern):
        [2026-10-08 04:02:11] [INFO] Text
        [2026-10-08 04:02:11] [GUI] [ERROR] Text        (Quelle, dann Stufe)
        [2026-10-08 04:02:11] [INFO] [SILENT-DONE] Text (Marke im Text)
    Zeilen ohne Zeitstempel (Fortsetzungen) gehoeren zur Zeile davor.
#>

$script:PA_Stufen = @('INFO', 'SUCCESS', 'WARNING', 'ERROR')

function ConvertTo-ProtokollEintraege {
    # -> Liste von @{ Datum; Zeit; Stufe; Text }. Trennerzeilen (====) und
    #    leere Zeilen fallen weg; Fortsetzungszeilen werden angehaengt.
    param([string[]]$Zeilen)
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($roh in @($Zeilen)) {
        if ($null -eq $roh) { continue }
        $z = $roh.TrimEnd()
        if (-not $z.Trim()) { continue }
        if ($z -match '^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] \[[A-Za-z-]+\] ={10,}\s*$') { continue }
        if ($z -match '^\[(\d{4}-\d\d-\d\d) (\d\d:\d\d):\d\d\] \[([A-Za-z-]+)\](?: \[([A-Za-z-]+)\])?\s?(.*)$') {
            $stufe = $Matches[3].ToUpperInvariant()
            $text = $Matches[5]
            if ($script:PA_Stufen -notcontains $stufe) {
                # Erst die Quelle ([GUI], [SILENT-DONE] ...), dann die Stufe.
                if ($Matches[4] -and ($script:PA_Stufen -contains $Matches[4].ToUpperInvariant())) {
                    $stufe = $Matches[4].ToUpperInvariant()
                } else {
                    $text = "[$($Matches[3])] " + $(if ($Matches[4]) { "[$($Matches[4])] " } else { '' }) + $text
                    $stufe = 'INFO'
                }
            } elseif ($Matches[4]) {
                $text = "[$($Matches[4])] $text"
            }
            $liste.Add(@{ Datum = $Matches[1]; Zeit = $Matches[2]; Stufe = $stufe; Text = $text.Trim() })
        } elseif ($liste.Count -gt 0) {
            $liste[$liste.Count - 1].Text += "`n" + $z.Trim()
        }
    }
    return , $liste.ToArray()
}

function Gruppiere-ProtokollTage {
    # -> Tage, neuester zuerst; je Tag die Eintraege in zeitlicher Reihenfolge.
    #    -NurFehler: nur Stufe ERROR.
    param($Eintraege, [switch]$NurFehler)
    $nach = [ordered]@{}
    foreach ($e in @($Eintraege)) {
        if ($NurFehler -and $e.Stufe -ne 'ERROR') { continue }
        if (-not $nach.Contains($e.Datum)) { $nach[$e.Datum] = New-Object System.Collections.Generic.List[object] }
        $nach[$e.Datum].Add($e)
    }
    $tage = @()
    foreach ($d in ($nach.Keys | Sort-Object -Descending)) {
        $tage += , @{ Datum = $d; Eintraege = $nach[$d].ToArray() }
    }
    return , $tage
}

function Get-ProtokollZaehler {
    param($Eintraege)
    $f = 0; $w = 0
    foreach ($e in @($Eintraege)) {
        if ($e.Stufe -eq 'ERROR') { $f++ } elseif ($e.Stufe -eq 'WARNING') { $w++ }
    }
    return @{ Fehler = $f; Warnungen = $w }
}

function Get-TagesKopf {
    # "Heute, 8. Oktober 2026" / "Gestern, ..." / "Mittwoch, 7. Oktober 2026"
    param([string]$Datum, [datetime]$Heute = (Get-Date))
    try {
        $d = [datetime]::ParseExact($Datum, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    } catch { return $Datum }
    $de = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $voll = $d.ToString('d. MMMM yyyy', $de)
    $diff = ($Heute.Date - $d.Date).Days
    if ($diff -eq 0) { return "Heute, $voll" }
    if ($diff -eq 1) { return "Gestern, $voll" }
    return $d.ToString('dddd', $de) + ", $voll"
}

function Get-StufenZeichen {
    # Zeichen UND Wort tragen die Bedeutung, nie die Farbe allein.
    param([string]$Stufe)
    switch ($Stufe) {
        'SUCCESS' { return [string][char]0x2713 }   # Haken
        'WARNING' { return [string][char]0x26A0 }   # Warndreieck
        'ERROR'   { return [string][char]0x2716 }   # schweres Kreuz
        default   { return [string][char]0x2139 }   # Info
    }
}

function Get-LetzterLauf {
    <#
        Was der letzte STILLE Lauf getan hat, als Daten (die Zeile im Kopf
        liest dieselbe Quelle als Text, Lies-LetztenLauf im Fenster).
        -> @{ Gefunden; Wann; Gescheitert; Fehler; Anzahl }
        Fehler und Anzahl nur aus diesem Lauf (ab "Silent Mode gestartet").
    #>
    param($Eintraege)
    $e = @($Eintraege)
    $ende = -1
    for ($i = $e.Count - 1; $i -ge 0; $i--) {
        if ($e[$i].Text -match 'SILENT-(DONE|FAILED)') { $ende = $i; break }
    }
    if ($ende -lt 0) { return @{ Gefunden = $false; Wann = ''; Gescheitert = $false; Fehler = 0; Anzahl = 0 } }
    $start = 0
    for ($i = $ende; $i -ge 0; $i--) {
        if ($e[$i].Text -match 'Silent Mode gestartet') { $start = $i; break }
    }
    $fehler = 0; $anzahl = 0
    for ($i = $start; $i -le $ende; $i++) {
        if ($e[$i].Stufe -eq 'ERROR') { $fehler++ }
        # Erst die Zeile erkennen, dann die Zahl: Das zweite -match wuerde die
        # Treffer des ersten ueberschreiben.
        if ($e[$i].Text -match '^(Aktualisiert|Updated):' -and $e[$i].Text -match '\((\d+) [^)]*\)\s*$') { $anzahl += [int]$Matches[1] }
    }
    return @{
        Gefunden    = $true
        Wann        = "$($e[$ende].Datum) $($e[$ende].Zeit)"
        Gescheitert = ($e[$ende].Text -match 'SILENT-FAILED')
        Fehler      = $fehler
        Anzahl      = $anzahl
    }
}

function Bilde-ErgebnisKarte {
    <#
        Die Standardansicht in einem Satz: Zahl, Satz, Ton.
        Ton: gut | warn | schlecht | neutral.
        -> @{ Zahl; Satz; Ton }
    #>
    param($Lauf)
    if (-not $Lauf.Gefunden) { return @{ Zahl = [string][char]0x2013; Satz = 'Noch kein stiller Lauf im Protokoll.'; Ton = 'neutral' } }
    $n = [int]$Lauf.Anzahl
    $f = [int]$Lauf.Fehler
    if ($Lauf.Gescheitert) {
        return @{ Zahl = '!'; Satz = 'Der letzte Lauf ist gescheitert. Er wird nachgeholt.'; Ton = 'schlecht' }
    }
    if ($n -gt 0 -and $f -eq 0) {
        $wort = if ($n -eq 1) { 'Es gab 1 Update, erfolgreich installiert.' } else { "Es gab $n Updates, alle erfolgreich installiert." }
        return @{ Zahl = "$n"; Satz = $wort; Ton = 'gut' }
    }
    if ($n -gt 0) {
        $fw = if ($f -eq 1) { '1 Fehler' } else { "$f Fehler" }
        return @{ Zahl = "$n"; Satz = "$n installiert, $fw. Einzelheiten unter Details."; Ton = 'warn' }
    }
    if ($f -gt 0) {
        $fw = if ($f -eq 1) { '1 Fehler' } else { "$f Fehler" }
        return @{ Zahl = '!'; Satz = "Der Lauf endete mit $fw. Einzelheiten unter Details."; Ton = 'warn' }
    }
    return @{ Zahl = '0'; Satz = 'Alles aktuell. Nichts zu tun.'; Ton = 'neutral' }
}

function Get-LaufAnzahl {
    # Wie viele stille Laeufe stehen im Protokoll (jeder endet mit SILENT-DONE oder SILENT-FAILED).
    param($Eintraege)
    $n = 0
    foreach ($e in @($Eintraege)) { if ($e.Text -match 'SILENT-(DONE|FAILED)') { $n++ } }
    return $n
}
