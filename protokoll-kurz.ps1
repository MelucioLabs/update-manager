# Kurzes, lesbares Protokoll: weniger Zeilen, eine Uebersicht je Lauf.
#
# WARUM (29.10.2026, Davids Wunsch): Das Protokoll war lang und schwer zu
# ueberfliegen; ob etwas aktualisiert wurde, ob etwas fehlschlug und ob ein
# Neustart ansteht, musste man aus 20 bis 40 Zeilen zusammensuchen.
#
# Zwei Dinge, beide ohne die Arbeit des Managers anzufassen:
#   1. Reine Routinezeilen (Konfiguration geladen, Internet OK, Hardware-
#      Erkennung ...) landen nicht mehr in der DATEI. Auf der Konsole bleiben
#      sie. Warnungen und Fehler werden NIE gefiltert.
#      Wieder alles in die Datei: "protokoll": { "ausfuehrlich": true } in
#      update-config.local.json.
#   2. Am Ende jedes Laufs steht eine kleine Tabelle: Quelle, Ergebnis, Hinweis.
#
# Die Tabelle wird aus den Zeilen DIESES Laufs gebaut ($Global:LaufZeilen,
# die Write-Log fuellt), auch aus den herausgefilterten. Die Zuordnung zur
# Quelle laeuft ueber Stichworte im Text; sie ist eine Ansicht, keine Buchfuehrung.

# Standalone-Fallbacks: Im Manager steht Write-Log im Kern und gewinnt, weil
# es nach dem Laden dieser Datei neu definiert wird. Allein geladen (Probe,
# Handaufruf) und fuer den Aufruf-Waechter bleibt die Datei in sich vollstaendig.
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') Write-Host $Message }
}

$Global:LaufZeilen = [System.Collections.Generic.List[object]]::new()
$Global:ProtokollAusfuehrlich = $false
$Global:LogQuelle = $null

function Set-LogQuelle {
    # Ab jetzt gehoeren neue Zeilen zu dieser Quelle (Winget, Chocolatey, Windows, Store, Treiber, BIOS).
    param([string]$Name)
    $Global:LogQuelle = $Name
}

$Script:ProtokollRauschen = @(
    '^(Konfiguration geladen|Configuration loaded)',
    '^(Eigene Einstellungen geladen|Local settings loaded)',
    '^(Internetverbindung OK|Internet connection OK)$',
    '^(Winget verfügbar|Winget available)$',
    '^(Prüfe Voraussetzungen|Checking prerequisites)',
    '^(Erkenne Hardware|Detecting hardware)',
    '^(CPU|GPU|Mainboard): ',
    '^(Starte|Starting) .*(Update|Updates)',
    '^Winget --all output',
    '^Winget-Updates gefunden',
    '^Zweiter Lauf ohne erhoehte Rechte',
    '^Benutzer-Pakete: Nachlauf beendet'
) -join '|'

function Test-ProtokollRauschen {
    param([string]$Message, [string]$Level)
    if ($Global:ProtokollAusfuehrlich) { return $false }
    if ($Level -ne 'INFO' -and $Level -ne 'SUCCESS') { return $false }
    return ($Message -match $Script:ProtokollRauschen)
}

function Get-LaufQuelle {
    param([string]$Text, [string]$Gesetzt)
    if ($Gesetzt) { return $Gesetzt }
    if ($Text -match '^(CPU|GPU|Mainboard): ') { return $null }
    if ($Text -match '^BIOS')                                            { return 'BIOS' }
    if ($Text -match '(?i)chocolatey|choco')                             { return 'Chocolatey' }
    if ($Text -match '(?i)winget|Benutzer-Pakete')                       { return 'Winget' }
    if ($Text -match '(?i)windows.?update|PSWindowsUpdate|Windows-Update'){ return 'Windows' }
    if ($Text -match '(?i)store')                                        { return 'Store' }
    if ($Text -match '(?i)nvidia|geforce|radeon|\bamd\b|\bmsi\b|intel.*(assistant|dsa)') { return 'Treiber' }
    return $null
}

function Get-LaufUebersicht {
    <#
        Gibt je Quelle ein Objekt zurueck: Quelle, Status (OK, WARNUNG,
        FEHLER, nichts), Hinweis, Neustart ($true/$false). Reihenfolge fest.
    #>
    param([object[]]$Zeilen = @($Global:LaufZeilen))

    $reihe = 'Winget', 'Chocolatey', 'Windows', 'Store', 'Treiber', 'BIOS'
    $ergebnis = @()
    foreach ($q in $reihe) {
        $z = @($Zeilen | Where-Object { (Get-LaufQuelle $_.Text $_.Quelle) -eq $q })
        if ($z.Count -eq 0) { continue }

        $fehler = @($z | Where-Object { $_.Level -eq 'ERROR' })
        $warn   = @($z | Where-Object { $_.Level -eq 'WARNING' })
        $status = if ($fehler.Count) { 'FEHLER' } elseif ($warn.Count) { 'WARNUNG' } else { 'OK' }

        $hinweis = if ($fehler.Count) { $fehler[0].Text }
                   elseif ($warn.Count) { $warn[0].Text }
                   else {
                       $gut = @($z | Where-Object { $_.Text -match '(?i)^(Aktualisiert|Updated|Keine|No updates|Store-Updates|Angestossen|Triggered)|aktuell|verfügbar\.|abgeschlossen' })
                       if ($gut.Count) { $gut[-1].Text } else { ($z[-1]).Text }
                   }
        if ($status -ne 'OK') {
            $ok = @($z | Where-Object { $_.Level -eq 'SUCCESS' -and $_.Text -match '^(Aktualisiert|Updated): .*\((\d+) ' })
            if ($ok.Count -and $ok[-1].Text -match '\((\d+) ') { $hinweis = "$($Matches[1]) aktualisiert; $hinweis" }
        }
        $hinweis = ($hinweis -replace '\s+', ' ' -replace '^BIOS: ', '').Trim()
        if ($hinweis.Length -gt 110) { $hinweis = $hinweis.Substring(0, 107) + '...' }

        $neustart = [bool]@($z | Where-Object { $_.Text -match '(?i)neustart (erforderlich|nötig|noetig|steht an)|(restart|reboot) (is )?(required|pending)' }).Count

        $ergebnis += [pscustomobject]@{ Quelle = $q; Status = $status; Hinweis = $hinweis; Neustart = $neustart }
    }
    return $ergebnis
}

function Write-LaufUebersicht {
    <#
        Schreibt die Tabelle ins Protokoll (und auf die Konsole). Zeilen mit
        FEHLER/WARNUNG gehen als WARNING hinein, NICHT als ERROR: Der Fehler
        steht im Protokoll schon einmal, und ein zweites ERROR wuerde den
        Exit-Code und die Fehlerzaehlung des Laufs doppelt belasten.
    #>
    param([double]$Minuten = -1)

    Set-LogQuelle $null
    $tab = @(Get-LaufUebersicht)
    if ($tab.Count -eq 0) { return }

    $kopf = 'Übersicht'
    if ($Minuten -ge 0) { $kopf += " ($Minuten min)" }
    Write-Log $kopf 'INFO'
    foreach ($r in $tab) {
        $mark = if ($r.Neustart) { '  [Neustart nötig]' } else { '' }
        $zeile = ('  {0,-11} {1,-8} {2}{3}' -f $r.Quelle, $r.Status, $r.Hinweis, $mark)
        Write-Log $zeile $(if ($r.Status -eq 'OK') { 'INFO' } else { 'WARNING' })
    }
    $n = @($tab | Where-Object { $_.Neustart }).Count
    if ($n -gt 0) {
        Write-Log ('  Neustart nötig: ja (' + ((@($tab | Where-Object { $_.Neustart } | ForEach-Object { $_.Quelle })) -join ', ') + ')') 'WARNING'
    }
}
