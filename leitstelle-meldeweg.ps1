# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Meldeweg zur Leitstelle im Portal (Welle 3, PR 3308): derselbe Weg, den
    die Wachen auf dem Host nutzen (infra/ops/wachen-basis.sh, wache_zeile/
    wache_tafel) - Portal-API, nur vom Host, POST
    /api/leitstelle/intern/meldungen, Kopf X-Leitstelle-Token aus der .env
    der portal-api. Keine zweite Infrastruktur.

    Der Aufrufer (Kern: Send-Fehlermeldung) baut und maskiert den Text und
    entscheidet anhand des Rueckgabewerts, ob der zweite Weg (ntfy) dran
    ist. Diese Datei tut nur den Transport und wirft nichts: Eine Meldung,
    die nicht rausgeht, darf den Lauf nicht kippen.

    Das Geheimnis wird nur auf dem Server gelesen (ueber ssh, wie
    leitstelle.sh es haelt): es steht in keiner Kommandozeile auf dieser
    Maschine und in keiner Datei im Repo. Scheitert der Weg (kein ssh,
    kein Host-Eintrag, kein Token), kommt $false zurueck.
#>

Set-StrictMode -Version Latest

function Send-TafelMeldung {
    <#
        Eine fertige (bereits maskierte) Meldung als Zeile auf die Tafel
        der Leitstelle im Portal schieben. Zwei Schritte, wie wache_tafel
        es vorlegt: 1. Body-Datei per scp auf den Host legen, 2. dort per
        curl posten - der Kopf kommt aus stdin (printf | curl -H @-), der
        Body aus der Datei. Rueckgabe: $true nur bei HTTP 200 vom Host.
    #>
    param(
        [string]$Text,
        [string]$Thema = 'update-manager',
        [string]$Bezug = ''
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $token = ''
    try {
        $roh = & ssh -o BatchMode=yes -o ConnectTimeout=10 hetzner `
            'grep -m1 ''^LEITSTELLE_TOKEN='' ~/apps/portal-api/.env | cut -d= -f2-' 2>$null
        if ($LASTEXITCODE -eq 0) { $token = ([string]($roh -join '')).Trim() }
    } catch { }
    if (-not $token) { return $false }

    $bodyDatei = Join-Path ([System.IO.Path]::GetTempPath()) ("meldung-" + [guid]::NewGuid().ToString('N') + ".json")
    $fernDatei = '/tmp/meldung-body.json'
    try {
        @{ text = $Text; thema = $Thema; bezug = $Bezug } |
            ConvertTo-Json -Compress |
            Set-Content -LiteralPath $bodyDatei -Encoding UTF8

        & scp -q $bodyDatei "hetzner:$fernDatei"
        if ($LASTEXITCODE -ne 0) { return $false }

        # stdin von ssh liest hier niemand: T=$(...) haelt das Geheimnis nur
        # auf dem Host, printf gibt es als Kopfzeile an das curl dort.
        $fern = 'T=$(grep -m1 ''^LEITSTELLE_TOKEN='' ~/apps/portal-api/.env | cut -d= -f2-); ' +
                'printf ''X-Leitstelle-Token: %s\n'' "$T" | ' +
                'curl -s -m 15 -o /tmp/meldung-antwort.json -w ''%{http_code}'' ' +
                '-H @- -H ''Content-Type: application/json'' -X POST ' +
                "--data-binary @$fernDatei " +
                'http://127.0.0.1:3005/api/leitstelle/intern/meldungen'
        $code = & ssh -o BatchMode=yes -o ConnectTimeout=10 hetzner $fern 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        return ("$code".Trim() -eq '200')
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $bodyDatei -Force -ErrorAction SilentlyContinue
    }
}
