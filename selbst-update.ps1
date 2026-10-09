# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Selbst-Update des Update-Managers (Konzept: SELBST-UPDATE.md).

    NUR FUNKTIONEN. Beim Laden (Punkt davor) passiert nichts: kein Netz, keine
    Datei, kein Fenster. update-manager-gui.ps1 laedt die Datei und ruft die
    Funktionen auf; probe.ps1 ruft sie gegen gespeicherte Antworten und
    Attrappen auf.

    DREI STUFEN, jede fuer sich abschaltbar (update-config.json, eigene Werte
    in update-config.local.json, Abschnitt "selbstUpdate"):
      pruefen        Das Fenster fragt hoechstens einmal am Tag bei GitHub
                     nach der neuesten Fassung und zeigt einen Hinweis.
                     Vorgabe: an. Es wird nichts geladen.
      installieren   Der Knopf "Neue Version installieren". Vorgabe: AUS,
                     solange das Setup nicht signiert ist (SELBST-UPDATE.md,
                     Empfehlung: erst mit Signatur freischalten).
      (Signatur)     $script:SU_SignaturAussteller. Leer = noch nicht
                     signiert; dann startet ein Setup nur nach Pruefsumme UND
                     ausdruecklicher Bestaetigung im Fenster. Sobald hier ein
                     Aussteller steht, startet NIE ein unsigniertes oder
                     fremd signiertes Setup.

    SICHERHEIT: nur dieses Repo, nur HTTPS, Adresse aus der API-Antwort wird
    gegen einen festen Anfang geprueft, SHA-256 gegen SHA256SUMS.txt desselben
    Releases, Datei waehrend Pruefung und Start mit gesperrtem Schreibzugriff
    gehalten (kein Austausch dazwischen).
#>

$script:SU_ApiUrl           = 'https://api.github.com/repos/MelucioLabs/update-manager/releases/latest'
$script:SU_DownloadPraefix  = 'https://github.com/MelucioLabs/update-manager/releases/download/'
$script:SU_ReleasePraefix   = 'https://github.com/MelucioLabs/update-manager/releases/'
$script:SU_SetupMuster      = 'MelucioLabs-Update-Manager-Setup-{0}.exe'
$script:SU_SummenName       = 'SHA256SUMS.txt'
$script:SU_SignaturAussteller = ''
$script:SU_MaxSetupBytes    = 200MB

function ConvertTo-FassungVersion {
    # "v3.10.0", "3.3.0-rc1" -> [version]; alles andere -> $null.
    # Als [version], nicht als Text: Sonst ist 3.10.0 kleiner als 3.9.0.
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    $t = $Tag.Trim()
    if ($t.StartsWith('v') -or $t.StartsWith('V')) { $t = $t.Substring(1) }
    $t = $t.Split('-')[0]
    if ($t -notmatch '^\d+\.\d+(\.\d+){0,2}$') { return $null }
    try { return [version]$t } catch { return $null }
}

function Test-FassungNeuer {
    param([string]$Tag, [string]$Aktuell)
    $neu = ConvertTo-FassungVersion $Tag
    $alt = ConvertTo-FassungVersion $Aktuell
    if ($null -eq $neu -or $null -eq $alt) { return $false }
    return ($neu -gt $alt)
}

function Test-SelbstUpdateAdresse {
    # Nur https://github.com/MelucioLabs/update-manager/releases/download/...
    param([string]$Url, [string]$Praefix = $script:SU_DownloadPraefix)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if (-not $Url.StartsWith($Praefix, [StringComparison]::Ordinal)) { return $false }
    # Kein Zurueck aus dem Pfad, keine Zugangsdaten, keine Sonderzeichen.
    if ($Url -match '\.\.|@|\\|\s|%2e|%2f') { return $false }
    return $true
}

function Lies-Pruefsumme {
    # Zeile der Form "<64 Hex>  <Dateiname>" (auch mit "*" vor dem Namen).
    param([string]$Liste, [string]$Datei)
    foreach ($zeile in ($Liste -split "`r?`n")) {
        if ($zeile -match '^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
            if ($Matches[2] -ceq $Datei) { return $Matches[1].ToLowerInvariant() }
        }
    }
    return $null
}

function Test-FassungStimmig {
    # Name und beide Adressen gehoeren zu GENAU diesem Tag: Wer eine hohe
    # Versionsnummer mit den Dateien eines alten Releases mischt, bekaeme sonst
    # ein Downgrade, das Pruefsumme und Rueckfrage besteht.
    param($Fassung)
    try {
        $v = ConvertTo-FassungVersion "$($Fassung.Tag)"
        if ($null -eq $v) { return $false }
        $tag = "$($Fassung.Tag)".Trim()
        $ohneV = if ($tag.StartsWith('v')) { $tag.Substring(1) } else { $tag }
        $name = $script:SU_SetupMuster -f $ohneV
        if ("$($Fassung.SetupName)" -cne $name) { return $false }
        $basis = $script:SU_DownloadPraefix + $tag + '/'
        if ("$($Fassung.SetupUrl)" -cne ($basis + $name)) { return $false }
        if ("$($Fassung.SummenUrl)" -cne ($basis + $script:SU_SummenName)) { return $false }
        if (-not (Test-SelbstUpdateAdresse "$($Fassung.SetupUrl)") -or -not (Test-SelbstUpdateAdresse "$($Fassung.SummenUrl)")) { return $false }
        return $true
    } catch { return $false }
}

function Waehle-Fassung {
    <#
        Aus der Antwort von .../releases/latest die Angaben, die gebraucht
        werden, oder $null, wenn etwas nicht stimmt (Entwurf, Vorabfassung,
        fremde Adresse, Setup oder Summenliste fehlt). Tut nichts am Netz.
    #>
    param($Release)
    if ($null -eq $Release) { return $null }
    $p = $Release.PSObject.Properties
    foreach ($n in 'tag_name', 'html_url', 'assets', 'draft', 'prerelease') { if (-not $p[$n]) { return $null } }
    if ($Release.draft -or $Release.prerelease) { return $null }
    $version = ConvertTo-FassungVersion $Release.tag_name
    if ($null -eq $version) { return $null }
    if (-not "$($Release.html_url)".StartsWith($script:SU_ReleasePraefix, [StringComparison]::Ordinal)) { return $null }

    $tag = "$($Release.tag_name)".Trim()
    $ohneV = if ($tag.StartsWith('v')) { $tag.Substring(1) } else { $tag }
    $setupName = $script:SU_SetupMuster -f $ohneV
    $setup = @($Release.assets | Where-Object { $_.name -ceq $setupName }) | Select-Object -First 1
    $summen = @($Release.assets | Where-Object { $_.name -ceq $script:SU_SummenName }) | Select-Object -First 1
    if (-not $setup -or -not $summen) { return $null }
    if (-not (Test-SelbstUpdateAdresse $setup.browser_download_url)) { return $null }
    if (-not (Test-SelbstUpdateAdresse $summen.browser_download_url)) { return $null }

    $f = [pscustomobject]@{
        Tag       = $tag
        Version   = $version
        Notizen   = "$($Release.html_url)"
        SetupName = $setupName
        SetupUrl  = "$($setup.browser_download_url)"
        SummenUrl = "$($summen.browser_download_url)"
    }
    if (-not (Test-FassungStimmig $f)) { return $null }
    return $f
}

function Lies-SelbstUpdateSchalter {
    <#
        Liest "selbstUpdate" aus update-config.json, darueber (falls da)
        update-config.local.json. Fehlt etwas oder ist es unlesbar, gelten die
        sicheren Vorgaben: pruefen = an, installieren = AUS.
    #>
    param([string]$Ordner)
    $r = [pscustomobject]@{ Pruefen = $true; Installieren = $false }
    foreach ($name in 'update-config.json', 'update-config.local.json') {
        $pfad = Join-Path $Ordner $name
        if (-not (Test-Path -LiteralPath $pfad)) { continue }
        try {
            $k = Get-Content -LiteralPath $pfad -Raw -Encoding UTF8 | ConvertFrom-Json
            $a = $k.PSObject.Properties['selbstUpdate']
            if (-not $a -or $null -eq $a.Value) { continue }
            $w = $a.Value.PSObject.Properties
            if ($w['pruefen'] -and $w['pruefen'].Value -is [bool]) { $r.Pruefen = $w['pruefen'].Value }
            if ($w['installieren'] -and $w['installieren'].Value -is [bool]) { $r.Installieren = $w['installieren'].Value }
        } catch { }
    }
    return $r
}

function Lies-SelbstUpdateZustand {
    param([string]$Pfad)
    try {
        if (Test-Path -LiteralPath $Pfad) { return (Get-Content -LiteralPath $Pfad -Raw -Encoding UTF8 | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Schreibe-SelbstUpdateZustand {
    # $Fassung: Ergebnis von Waehle-Fassung oder $null (nichts Neues / nicht erreichbar).
    param([string]$Pfad, $Fassung, [string]$Ausgeblendet = '')
    try {
        $ordner = Split-Path -Parent $Pfad
        if (-not (Test-Path -LiteralPath $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }
        $f = $null
        if ($Fassung) {
            $f = [ordered]@{ tag = "$($Fassung.Tag)"; notizen = "$($Fassung.Notizen)"; setupName = "$($Fassung.SetupName)"
                             setupUrl = "$($Fassung.SetupUrl)"; summenUrl = "$($Fassung.SummenUrl)" }
        }
        [ordered]@{
            geprueft     = [datetime]::UtcNow.ToString('o')
            fassung      = $f
            ausgeblendet = $Ausgeblendet
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Pfad -Encoding UTF8
    } catch { }
}

function Lies-GemerkteFassung {
    # Die Datei liegt im Programmdaten-Ordner, ist aber fuer unerhoehte Prozesse
    # moeglicherweise beschreibbar: Sie wird wie eine Antwort aus dem Netz
    # behandelt (gleiche Pruefung) und wirft nie (StrictMode im Fenster).
    param($Zustand)
    try {
        if ($null -eq $Zustand) { return $null }
        $p = $Zustand.PSObject.Properties['fassung']
        if (-not $p -or $null -eq $p.Value) { return $null }
        $q = $p.Value.PSObject.Properties
        foreach ($n in 'tag', 'notizen', 'setupName', 'setupUrl', 'summenUrl') { if (-not $q[$n]) { return $null } }
        $f = [pscustomobject]@{
            Tag = "$($q['tag'].Value)"; Version = (ConvertTo-FassungVersion "$($q['tag'].Value)"); Notizen = "$($q['notizen'].Value)"
            SetupName = "$($q['setupName'].Value)"; SetupUrl = "$($q['setupUrl'].Value)"; SummenUrl = "$($q['summenUrl'].Value)"
        }
        if ($null -eq $f.Version) { return $null }
        if (-not $f.Notizen.StartsWith($script:SU_ReleasePraefix, [StringComparison]::Ordinal)) { return $null }
        if (-not (Test-FassungStimmig $f)) { return $null }
        return $f
    } catch { return $null }
}

function Test-HeuteSchonGefragt {
    # Hoechstens einmal am Tag: weniger als 24 Stunden seit der letzten Abfrage.
    param($Zustand, [datetime]$Jetzt = [datetime]::UtcNow)
    if ($null -eq $Zustand) { return $false }
    $p = $Zustand.PSObject.Properties['geprueft']
    if (-not $p -or [string]::IsNullOrWhiteSpace("$($p.Value)")) { return $false }
    try {
        $wann = [datetime]::Parse("$($p.Value)", [Globalization.CultureInfo]::InvariantCulture,
                                  [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $false }
    if ($wann -gt $Jetzt) { return $false }          # Uhr verstellt: lieber neu fragen
    return (($Jetzt - $wann) -lt [TimeSpan]::FromHours(24))
}

function Frage-NeuesteFassung {
    # Eine Abfrage, ein Ergebnis (Waehle-Fassung) oder $null. Netzfehler sind
    # still: Ein Fenster, das beim Oeffnen ueber fehlendes Netz klagt, nervt.
    param([string]$AktuelleVersion)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $kopf = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = "MelucioLabs-Update-Manager/$AktuelleVersion" }
        $antwort = Invoke-RestMethod -Uri $script:SU_ApiUrl -Headers $kopf -TimeoutSec 15 -ErrorAction Stop
        return (Waehle-Fassung $antwort)
    } catch { return $null }
}

function Lade-Setup {
    <#
        Laedt Setup und Summenliste in einen nur fuer Administratoren
        beschreibbaren Ordner und gibt @{ Pfad; Summe } zurueck. Wirft bei
        jedem Fehler (der Aufrufer meldet "nicht geklappt").
    #>
    param($Fassung, [string]$Ordner)
    if (-not (Test-SelbstUpdateAdresse $Fassung.SetupUrl) -or -not (Test-SelbstUpdateAdresse $Fassung.SummenUrl)) {
        throw 'Adresse nicht zugelassen'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Test-FassungStimmig $Fassung)) { throw 'Fassung stimmt nicht mit ihrem Tag ueberein' }
    # Der Oberordner liegt im Protokollbereich, der fuer unerhoehte Prozesse
    # beschreibbar sein kann: Ein Link (Junction) dort darf nicht dazu fuehren,
    # dass als Administrator woanders geloescht oder umberechtigt wird.
    if (Test-Path -LiteralPath $Ordner) {
        $o = Get-Item -LiteralPath $Ordner -Force
        if (-not $o.PSIsContainer -or ($o.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Ordner fuer das Setup ist ein Link' }
        # Reste frueherer Laeufe weg, Links dabei nicht verfolgen.
        foreach ($alt in Get-ChildItem -LiteralPath $Ordner -Force -ErrorAction SilentlyContinue) {
            if ($alt.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            Remove-Item -LiteralPath $alt.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        New-Item -ItemType Directory -Path $Ordner -Force | Out-Null
    }
    $Ordner = Join-Path $Ordner ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Ordner | Out-Null
    # Nur SYSTEM und Administratoren (SIDs, damit die Windows-Sprache egal ist).
    & icacls.exe $Ordner /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    $kopf = @{ 'User-Agent' = 'MelucioLabs-Update-Manager' }
    $summenText = (Invoke-WebRequest -Uri $Fassung.SummenUrl -Headers $kopf -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop).Content
    if ($summenText -is [byte[]]) { $summenText = [Text.Encoding]::ASCII.GetString($summenText) }
    $summe = Lies-Pruefsumme $summenText $Fassung.SetupName
    if (-not $summe) { throw 'Keine Pruefsumme fuer das Setup in der Liste' }
    $pfad = Join-Path $Ordner $Fassung.SetupName
    Invoke-WebRequest -Uri $Fassung.SetupUrl -Headers $kopf -OutFile $pfad -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
    return @{ Pfad = $pfad; Summe = $summe }
}

function Installiere-Setup {
    <#
        Prueft und startet ein heruntergeladenes Setup. Gibt
        @{ Gestartet; ExitCode; Meldung} zurueck, wirft nicht.

        Die Datei wird mit gesperrtem Schreibzugriff geoeffnet und GEHALTEN,
        bis das Setup beendet ist: Zwischen Pruefsumme und Start kann sie
        niemand tauschen.

        -UnsigniertErlaubt: nur wirksam, solange $script:SU_SignaturAussteller
        leer ist (noch nicht signiert). Danach nie.
    #>
    param(
        [string]$Pfad,
        [string]$ErwarteteSumme,
        [switch]$UnsigniertErlaubt,
        [string[]]$Argumente = @('/SILENT', '/NORESTART')
    )
    $nein = { param($m) @{ Gestartet = $false; ExitCode = $null; Meldung = $m } }
    if ([string]$ErwarteteSumme -notmatch '^[0-9a-fA-F]{64}$') { return (& $nein 'Keine gueltige Pruefsumme') }
    $strom = $null
    try {
        $info = Get-Item -LiteralPath $Pfad -ErrorAction Stop
        if ($info.Length -lt 1024 -or $info.Length -gt $script:SU_MaxSetupBytes) { return (& $nein 'Dateigroesse unplausibel') }
        $strom = [System.IO.File]::Open($Pfad, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $ist = ([BitConverter]::ToString($sha.ComputeHash($strom)) -replace '-', '').ToLowerInvariant()
        if ($ist -ne $ErwarteteSumme.ToLowerInvariant()) { return (& $nein 'Pruefsumme stimmt nicht') }

        if ($script:SU_SignaturAussteller) {
            $sig = Get-AuthenticodeSignature -FilePath $Pfad
            $okSig = ($sig.Status -eq 'Valid') -and $sig.SignerCertificate -and
                     ($sig.SignerCertificate.Subject -match ('(^|, )CN=' + [regex]::Escape($script:SU_SignaturAussteller) + '(,|$)'))
            if (-not $okSig) { return (& $nein 'Signatur fehlt oder stammt nicht vom erwarteten Aussteller') }
        } elseif (-not $UnsigniertErlaubt) {
            return (& $nein 'Setup ist noch unsigniert und wurde nicht bestaetigt')
        }

        $p = Start-Process -FilePath $Pfad -ArgumentList $Argumente -PassThru -ErrorAction Stop
        $p.WaitForExit()
        $code = $p.ExitCode
        return @{ Gestartet = $true; ExitCode = $code; Meldung = $(if ($code -eq 0) { 'Installiert' } else { "Setup endete mit Code $code" }) }
    } catch {
        return (& $nein "Nicht gestartet: $($_.Exception.Message)")
    } finally {
        if ($strom) { $strom.Dispose() }
    }
}
