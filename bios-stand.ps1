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
# keinen vergleichbar lesbaren Katalog (MSI liefert HTTP 403); dort sagt der
# Bericht das, statt eine Aktualitaet zu behaupten, und nennt nur den Stand
# und die Support-Seite.
#
# Dazu auf JEDEM Rechner (auch MSI/Eigenbau): CPU, Mainboard, geladener
# Intel-Microcode und BIOS-Alter. Eine Warnung gibt es, wenn der Microcode unter
# der Schwelle aus update-config.json (hardwareStand) liegt oder das BIOS aelter
# als biosMaxAlterMonate ist. Gemessen wird nur lesend (CIM, Registry).
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
    $g = [ordered]@{ Hersteller = ''; Modell = ''; Mainboard = ''; Produkt = ''; BiosVersion = ''; BiosDatum = ''; Typ = '' }
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
        # Firmware-Text: Umbrueche zu Leerzeichen, sonst koennte er Protokollzeilen bauen.
        $g.Mainboard = ("$($bb.Manufacturer) $($bb.Product)" -replace '\s+', ' ').Trim()
        $g.Produkt = "$($bb.Product)".Trim()
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

function Get-HardwareKonfig {
    <#
        Abschnitt "hardwareStand" aus der Konfiguration: Mindest-Microcode je
        CPU-Familie, BIOS-Hoechstalter, Support-Links. Die Schwellen stehen in
        update-config.json (eigene Werte in update-config.local.json), NICHT im
        Code: Intel hebt sie mit jeder Microcode-Runde an. Im Manager liegt die
        zusammengefuehrte Konfiguration in $Global:Config; allein geladen (Probe,
        Handaufruf) wird die Datei neben diesem Skript gelesen. Fehlt der
        Abschnitt, wird nichts geprueft und der Bericht sagt das.
    #>
    if ($Global:Config -and $Global:Config.PSObject.Properties['hardwareStand']) { return $Global:Config.hardwareStand }
    try {
        $pfad = Join-Path $PSScriptRoot 'update-config.json'
        if (Test-Path $pfad) {
            $c = Get-Content $pfad -Raw | ConvertFrom-Json
            if ($c.PSObject.Properties['hardwareStand']) { return $c.hardwareStand }
        }
    } catch { }
    return $null
}

function Get-CpuMicrocode {
    <#
        CPU-Name und geladenen Microcode (nur lesen: Registry
        HKLM\HARDWARE\...\CentralProcessor\0, "Update Revision", ohne Rechte
        lesbar). Intel legt die Revision in die unteren vier Bytes, aeltere
        Boards in die oberen: ist die untere Haelfte null, zaehlt die obere.
    #>
    $c = [ordered]@{ Cpu = ''; Anbieter = ''; Microcode = $null }
    try {
        # Registry-API statt Get-ItemProperty: Das Cmdlet wirft hier (gemessen
        # am Laptop) "Byte[] nach Int32", weil es alle Werte der Gruppe liest,
        # auch die binaeren.
        $reg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('HARDWARE\DESCRIPTION\System\CentralProcessor\0')
        if (-not $reg) { return [pscustomobject]$c }
        $c.Cpu = "$($reg.GetValue('ProcessorNameString'))".Trim() -replace '\s+', ' '
        $c.Anbieter = "$($reg.GetValue('VendorIdentifier'))".Trim()
        $b = [byte[]]$reg.GetValue('Update Revision')
        $reg.Close()
        if ($b -and $b.Count -ge 4) {
            $niedrig = [BitConverter]::ToUInt32($b, 0)
            $hoch = if ($b.Count -ge 8) { [BitConverter]::ToUInt32($b, 4) } else { 0 }
            $wert = if ($niedrig -ne 0) { $niedrig } else { $hoch }
            if ($wert -ne 0) { $c.Microcode = [uint32]$wert }
        }
    } catch { }
    return [pscustomobject]$c
}

function ConvertTo-MicrocodeZahl {
    <# "0x12F" -> 303; sonst $null. #>
    param([string]$Text)
    if ($Text -match '^0x([0-9A-Fa-f]{1,8})$') { return [Convert]::ToUInt32($Matches[1], 16) }
    return $null
}

function Test-MicrocodeSchwelle {
    <#
        Gibt die erste passende Regel mit Ergebnis zurueck (Name, Minimum,
        Unterschritten) oder $null, wenn keine Regel zur CPU passt. Nur Intel:
        AMD zaehlt Microcode-Revisionen anders, ein Vergleich waere erfunden.
    #>
    param([string]$Cpu, [string]$Anbieter, $Microcode, $Regeln)
    if ($Anbieter -notmatch 'Intel') { return $null }
    foreach ($regel in @($Regeln)) {
        if (-not $regel -or -not $regel.cpuMuster) { continue }
        # Ein kaputter Ausdruck in der Konfiguration ueberspringt nur seine Regel.
        try { if ($Cpu -notmatch "$($regel.cpuMuster)") { continue } } catch { continue }
        $min = ConvertTo-MicrocodeZahl "$($regel.minimum)"
        if ($null -eq $min) { continue }
        return [pscustomobject]@{
            Name         = "$($regel.name)"
            Minimum      = $min
            Unterschritten = ($null -ne $Microcode -and [uint32]$Microcode -lt $min)
        }
    }
    return $null
}

function Get-BiosAlterMonate {
    <# Alter des BIOS-Datums (yyyy-MM-dd) in vollen Monaten; $null, wenn unlesbar. #>
    param([string]$Datum, [datetime]$Heute = (Get-Date))
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Datum, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, 'None', [ref]$d)) { return $null }
    $m = ($Heute.Year - $d.Year) * 12 + ($Heute.Month - $d.Month)
    if ($Heute.Day -lt $d.Day) { $m-- }
    return [Math]::Max(0, $m)
}

function Get-SupportLink {
    <# Support-Seite des Herstellers aus der Konfiguration, oder ''. {Produkt} wird aus dem Boardnamen gebaut. #>
    param($Geraet, $Konfig)
    if (-not $Konfig -or -not $Konfig.PSObject.Properties['supportLinks']) { return '' }
    # Produkt ohne Klammer: "PRO H610M-G (MS-7D46)" -> PRO-H610M-G
    $produkt = ("$($Geraet.Produkt)" -replace '\s*\(.*$', '' -replace '[^A-Za-z0-9]+', '-').Trim('-')
    foreach ($l in @($Konfig.supportLinks)) {
        if (-not $l.hersteller -or "$($Geraet.Hersteller) $($Geraet.Mainboard)" -notmatch "$($l.hersteller)") { continue }
        $url = "$($l.url)"
        if ($url -notmatch '^https://') { continue }
        if ($url -match '\{Produkt\}') {
            if ($produkt -match '^[A-Za-z0-9-]{3,40}$') { return ($url -replace '\{Produkt\}', $produkt) }
            if ($l.PSObject.Properties['allgemein'] -and "$($l.allgemein)" -match '^https://') { return "$($l.allgemein)" }
            continue
        }
        return $url
    }
    return ''
}

function Get-HardwareBericht {
    <#
        Messen ohne Rechte, nur lesen: CPU, Mainboard, Microcode, BIOS-Alter,
        Support-Link, dazu die Warnungen (Liste von Zeilen). Ohne Konfiguration
        wird nichts bewertet. Ein Ergebnis-Objekt, damit Show-BiosStand und die
        Probe dieselbe Quelle nutzen.
    #>
    param($Geraet = (Get-BiosGeraet), $Cpu = (Get-CpuMicrocode), $Konfig = (Get-HardwareKonfig), [datetime]$Heute = (Get-Date))

    $r = [ordered]@{
        Zeile = ''; Warnungen = @(); MicrocodeText = ''; Link = ''; AlterMonate = $null; MicrocodeUnterschritten = $false
    }
    $mcText = if ($null -ne $Cpu.Microcode) { '0x{0:X}' -f [uint32]$Cpu.Microcode } else { 'nicht lesbar' }
    $r.MicrocodeText = $mcText
    $r.Zeile = "Hardware: CPU $($Cpu.Cpu), Mainboard $($Geraet.Mainboard), Microcode $mcText"
    $r.Link = Get-SupportLink -Geraet $Geraet -Konfig $Konfig

    if (-not $Konfig) {
        $r.Zeile += '. Keine Schwellen in der Konfiguration (hardwareStand), nichts bewertet.'
        return [pscustomobject]$r
    }

    $w = @()
    $treffer = Test-MicrocodeSchwelle -Cpu $Cpu.Cpu -Anbieter $Cpu.Anbieter -Microcode $Cpu.Microcode -Regeln $Konfig.microcode
    if ($treffer -and $treffer.Unterschritten) {
        $r.MicrocodeUnterschritten = $true
        $w += "Microcode $mcText liegt unter dem Mindestwert 0x{0:X} ($($treffer.Name)). Neueres BIOS des Herstellers von Hand prüfen." -f $treffer.Minimum
    } elseif ($treffer -and $null -eq $Cpu.Microcode) {
        $w += "Microcode nicht lesbar, Mindestwert 0x{0:X} ($($treffer.Name)) nicht prüfbar." -f $treffer.Minimum
    }

    $max = 12
    if ($Konfig.PSObject.Properties['biosMaxAlterMonate'] -and "$($Konfig.biosMaxAlterMonate)" -match '^\d+$') { $max = [int]$Konfig.biosMaxAlterMonate }
    $r.AlterMonate = Get-BiosAlterMonate -Datum $Geraet.BiosDatum -Heute $Heute
    if ($null -ne $r.AlterMonate -and $r.AlterMonate -gt $max) {
        $w += "BIOS ist $($r.AlterMonate) Monate alt (vom $($Geraet.BiosDatum)), Grenze $max. Beim Hersteller auf ein neueres prüfen."
    }
    $r.Warnungen = $w
    return [pscustomobject]$r
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
        $r.Text = "$kopf. Kein abrufbarer Hersteller-Katalog, Aktualität nicht geprüft; Stand und Support-Seite siehe unten."
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
    # Ohne Katalog (alle ausser Lenovo) bleibt der Alters-Hinweis die einzige
    # Bewertung; bei "Aktuell" laut Hersteller waere er Laerm.
    $h = $null
    try { $h = Get-HardwareBericht -Geraet $b.Geraet } catch { Write-Log "BIOS: Hardware-Messung fehlgeschlagen ($($_.Exception.Message))" 'WARNING' }
    $warnungen = @()
    if ($h) {
        $warnungen = @($h.Warnungen | Where-Object { $b.Status -ne 'Aktuell' -or $_ -notmatch '^BIOS ist ' })
    }
    Write-Log "BIOS: $($b.Text)" $stufe
    if ($h) {
        Write-Log "BIOS: $($h.Zeile)" 'INFO'
        foreach ($w in $warnungen) { Write-Log "BIOS: $w" 'WARNING' }
        if ($warnungen.Count -gt 0 -and $h.Link) { Write-Log "BIOS: Support-Seite des Herstellers (nur lesen, nie automatisch einspielen): $($h.Link)" 'INFO' }
    }
    Set-LogQuelle $null
    return $b
}
