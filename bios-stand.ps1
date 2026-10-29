# BIOS-Stand: nur MESSEN und MELDEN, nie einspielen.
#
# WARUM (29.10.2026, Davids Wunsch): Der Manager soll sagen koennen, welches
# BIOS auf dem Rechner liegt und ob der Hersteller ein neueres anbietet.
# Einspielen bleibt Handarbeit: Ein BIOS-Update mitten in einem naechtlichen
# Lauf, ohne Netzteil-Pruefung und ohne jemanden vor dem Geraet, kann einen
# Rechner unbrauchbar machen. Darum steht hier kein Aufruf, der etwas
# installiert oder herunterlaedt (nur die kleinen XML-Beschreibungen).
#
# Quelle ist der oeffentliche Lenovo-Katalog, den auch Lenovo System Update
# liest: download.lenovo.com/catalog/<Typ>_Win11.xml. Andere Hersteller haben
# keinen vergleichbar lesbaren Katalog; dort sagt der Bericht das, statt eine
# Aktualitaet zu behaupten.
#
# Reine Funktionen, ohne Rechte lauffaehig (nur CIM-Lesen und HTTPS-GET).

# Standalone-Fallbacks: Im Manager steht Write-Log im Kern und gewinnt, weil
# es nach dem Laden dieser Datei neu definiert wird. Allein geladen (Probe,
# Handaufruf) und fuer den Aufruf-Waechter bleibt die Datei in sich vollstaendig.
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') Write-Host $Message }
}
if (-not (Get-Command Set-LogQuelle -ErrorAction SilentlyContinue)) {
    function Set-LogQuelle { param([string]$Name) }
}

function Get-BiosGeraet {
    <# Liest Hersteller, Modell, BIOS-Version und -Datum des Rechners. #>
    $g = [ordered]@{ Hersteller = ''; Modell = ''; Mainboard = ''; BiosVersion = ''; BiosDatum = ''; Typ = '' }
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object -First 1
        $g.BiosVersion = "$($bios.SMBIOSBIOSVersion)".Trim()
        if ($bios.ReleaseDate) { $g.BiosDatum = ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') }
        $g.Hersteller = "$($bios.Manufacturer)".Trim()
    } catch { }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
        if ($cs.Manufacturer) { $g.Hersteller = "$($cs.Manufacturer)".Trim() }
        $g.Modell = "$($cs.Model)".Trim()
    } catch { }
    try {
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        $g.Mainboard = "$($bb.Manufacturer) $($bb.Product)".Trim()
        # Lenovo: Win32_BaseBoard.Product ist der Maschinentyp (21MA000RGE),
        # die ersten vier Zeichen benennen den Katalog.
        if ($bb.Product -match '^([0-9A-Z]{4})') { $g.Typ = $Matches[1] }
    } catch { }
    return [pscustomobject]$g
}

function ConvertTo-BiosZahl {
    <# "R2JET48W(1.25 )" -> [version]1.25; sonst $null. #>
    param([string]$Text)
    if ($Text -match '\((\d+(?:\.\d+)+)\s*\)') { return [version]$Matches[1] }
    if ($Text -match '^\d+(?:\.\d+)+$') { return [version]$Text }
    return $null
}

function Get-BiosNeuesteLenovo {
    <#
        Liest den Lenovo-Katalog fuer den Maschinentyp und gibt die hoechste
        BIOS-Version zurueck (Version, Datum, Kennung) oder $null.
        Wirft bei Netzfehlern; der Aufrufer macht daraus "nicht pruefbar".
    #>
    param([string]$Typ, [int]$TimeoutSekunden = 20)
    if ($Typ -notmatch '^[0-9A-Z]{4}$') { return $null }

    $katalog = $null
    $letzter = $null
    foreach ($os in 'Win11', 'Win10') {
        try {
            $katalog = Invoke-RestMethod -Uri "https://download.lenovo.com/catalog/${Typ}_$os.xml" `
                -TimeoutSec $TimeoutSekunden -UseBasicParsing -ErrorAction Stop
            if ($katalog) { break }
        } catch { $letzter = $_ }
    }
    if (-not $katalog) { if ($letzter) { throw $letzter } else { return $null } }

    $xml = if ($katalog -is [xml]) { $katalog } else { [xml](([string]$katalog) -replace '^[^<]+', '') }
    $bios = @($xml.packages.package | Where-Object { $_.category -like 'BIOS*' })

    $beste = $null
    foreach ($p in $bios) {
        $uri = "$($p.location)"
        # Nur Lenovos eigener Host: Der Katalog ist Eingabe von aussen.
        if ($uri -notmatch '^https://download\.lenovo\.com/') { continue }
        try {
            $roh = Invoke-RestMethod -Uri $uri -TimeoutSec $TimeoutSekunden -UseBasicParsing -ErrorAction Stop
            $px = if ($roh -is [xml]) { $roh } else { [xml](([string]$roh) -replace '^[^<]+', '') }
            $v = ConvertTo-BiosZahl "$($px.Package.version)"
            if (-not $v) { continue }
            if (-not $beste -or $v -gt $beste.Version) {
                $beste = [pscustomobject]@{
                    Version = $v
                    # Nur Zahlen/Buchstaben ins Protokoll: Die Antwort ist Fremdtext,
                    # ein Zeilenumbruch darin koennte eine falsche Protokollzeile bauen.
                    Datum   = $(if ("$($px.Package.ReleaseDate)" -match '^\d{4}-\d{2}-\d{2}$') { $Matches[0] } else { '' })
                    Kennung = $(if ("$($px.Package.id)" -match '^[A-Za-z0-9]{1,20}$') { $Matches[0] } else { '' })
                }
            }
        } catch { }
    }
    return $beste
}

function Get-BiosBericht {
    <#
        Ein Ergebnis-Objekt: Status ist Aktuell, NeuerVorhanden, Unklar oder
        NichtPruefbar; Text ist die eine Zeile fuers Protokoll.
    #>
    $g = Get-BiosGeraet
    $kopf = "$($g.Hersteller) $($g.Modell), BIOS $($g.BiosVersion) ($($g.BiosDatum))"
    $r = [ordered]@{ Status = 'Unklar'; Text = ''; Geraet = $g; Neuestes = $null }

    if ($g.Hersteller -notmatch 'LENOVO') {
        $r.Text = "$kopf. Kein lesbarer Hersteller-Katalog eingebunden, Stand von Hand beim Hersteller prüfen."
        return [pscustomobject]$r
    }
    try {
        $neu = Get-BiosNeuesteLenovo -Typ $g.Typ
    } catch {
        $r.Status = 'NichtPruefbar'
        $r.Text = "$kopf. Lenovo-Katalog nicht erreichbar ($($_.Exception.Message))."
        return [pscustomobject]$r
    }
    if (-not $neu) {
        $r.Text = "$kopf. Der Katalog nennt für Typ $($g.Typ) kein BIOS."
        return [pscustomobject]$r
    }
    $r.Neuestes = $neu
    $inst = ConvertTo-BiosZahl $g.BiosVersion
    if (-not $inst) {
        $r.Text = "$kopf. Installierte Version nicht lesbar; Lenovo bietet $($neu.Version) ($($neu.Datum))."
    } elseif ($neu.Version -gt $inst) {
        $r.Status = 'NeuerVorhanden'
        $r.Text = "$kopf. NEUERES BIOS bei Lenovo: $($neu.Version) vom $($neu.Datum). Nur von Hand einspielen (Netzteil dran, Lenovo Vantage oder Support-Seite)."
    } else {
        $r.Status = 'Aktuell'
        $r.Text = "$kopf. Aktuell, Lenovo bietet höchstens $($neu.Version) ($($neu.Datum))."
    }
    return [pscustomobject]$r
}

function Show-BiosStand {
    <#
        Der Schritt im Manager: messen, EINE Zeile ins Protokoll. Aendert
        nichts am System. "Neueres vorhanden" ist eine Warnung (Handarbeit
        offen), kein Fehler: Es soll weder den Exit-Code des Laufs auf 5
        ziehen noch die Tagesmarke [SILENT-DONE] verhindern.
    #>
    Set-LogQuelle 'BIOS'
    $b = Get-BiosBericht
    $stufe = switch ($b.Status) {
        'Aktuell'        { 'SUCCESS' }
        'NeuerVorhanden' { 'WARNING' }
        'NichtPruefbar'  { 'WARNING' }
        default          { 'INFO' }
    }
    Write-Log "BIOS: $($b.Text)" $stufe
    Set-LogQuelle $null
    return $b
}
