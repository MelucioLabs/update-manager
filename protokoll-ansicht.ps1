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
    # Bilingual (David's finding, 25.11.2026): the words come from the GUI
    # language table, the date pattern from the culture behind $Sprache.
    param([string]$Datum, [datetime]$Heute = (Get-Date), [hashtable]$SprachTabelle, [string]$Sprache = 'de')
    try {
        $d = [datetime]::ParseExact($Datum, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    } catch { return $Datum }
    $kultur = if ($Sprache -eq 'en') { 'en-US' } else { 'de-DE' }
    $ci = [Globalization.CultureInfo]::GetCultureInfo($kultur)
    $muster = if ($Sprache -eq 'en') { 'MMMM d, yyyy' } else { 'd. MMMM yyyy' }
    $voll = $d.ToString($muster, $ci)
    $heuteW = $SprachTabelle['tageskopf_heute']
    $gesternW = $SprachTabelle['tageskopf_gestern']
    $diff = ($Heute.Date - $d.Date).Days
    if ($diff -eq 0) { return "$heuteW, $voll" }
    if ($diff -eq 1) { return "$gesternW, $voll" }
    return $d.ToString('dddd', $ci) + ", $voll"
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
        Die Saetze kommen aus der Sprachtabelle (gui-sprache.ps1); im
        englischen Fenster zeigte diese Karte sonst deutschen Wortlaut
        (Davids Befund 25.11.2026).
        -> @{ Zahl; Satz; Ton }
    #>
    param($Lauf, [hashtable]$SprachTabelle)
    if (-not $Lauf.Gefunden) { return @{ Zahl = [string][char]0x2013; Satz = $SprachTabelle['noch_kein_stiller']; Ton = 'neutral' } }
    $n = [int]$Lauf.Anzahl
    $f = [int]$Lauf.Fehler
    if ($Lauf.Gescheitert) {
        return @{ Zahl = '!'; Satz = $SprachTabelle['ergeb_gescheitert_lang']; Ton = 'schlecht' }
    }
    if ($n -gt 0 -and $f -eq 0) {
        $satz = if ($n -eq 1) { $SprachTabelle['ergeb_install_eins'] } else { $SprachTabelle['ergeb_installiert_format'] -f $n }
        return @{ Zahl = "$n"; Satz = $satz; Ton = 'gut' }
    }
    $fw = $SprachTabelle['fehler_zaehl_format'] -f $f
    if ($n -gt 0) {
        return @{ Zahl = "$n"; Satz = ($SprachTabelle['ergeb_teilweise_format'] -f $n, $fw); Ton = 'warn' }
    }
    if ($f -gt 0) {
        return @{ Zahl = '!'; Satz = ($SprachTabelle['ergeb_endete_format'] -f $fw); Ton = 'warn' }
    }
    return @{ Zahl = '0'; Satz = $SprachTabelle['ergeb_alles_aktuell']; Ton = 'neutral' }
}
