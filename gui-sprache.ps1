# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Sprache und Einstellungen der Oberflaeche (update-manager-gui.ps1).

    NUR FUNKTIONEN und zwei Tabellen. Beim Laden passiert nichts: keine Datei,
    kein Netz, kein Fenster. Das Fenster laedt die Datei per Punkt und baut
    daraus $T; probe.ps1 liest die Tabellen und ruft die Funktionen gegen
    Temp-Ordner auf.

    ZWEI TABELLEN, nicht Sprachdateien (MEHRSPRACHIG.md schlaegt lang/ vor;
    fuer zwei Sprachen ist das noch kein eigener Ordner wert). Genau wie im
    Kern: ein Schluessel, zwei Faesser, Deutsch zuerst. Die Probe erzwingt,
    dass jeder benutzte Schluessel in BEIDEN Tabellen steht, und der
    Fenster-Aufbau bricht ab, solange ein __T_schluessel__ unerwartet bleibt.

    EINSTELLUNGEN. Gelesen werden update-config.json und darueber
    update-config.local.json (gleiche Ordnung wie im Kern). GESCHRIEBEN wird
    NUR die lokale Datei: update-config.json gehoert zum Werkzeug und liegt
    im Repo, eigene Werte dort waeren beim naechsten Abruf weg. Die
    Vorgaben (Seed-Defaults: Deutsch, alle Quellen an, Pruefung an) stehen
    in update-config.json, die Maschine setzt sie in der lokalen Datei herab.

    AUTO-INSTALL BLEIBT AUS. SelbstUpdate.installieren wird hier nie
    geschrieben und nie auf true gelesen angeboten: solange das Setup nicht
    signiert ist (CODE-SIGNING-POLICY.md), zeigt der Manager hoechstens den
    Hinweis auf eine neue Fassung.
#>

# BOM noetig (Windows PowerShell 5.1 liest sonst Windows-1252), echte
# Umlaute, Code-Kommentare englisch.

$script:GuiTabelleDe = @{
    # Kopf
    "kern_fehlt_format"      = "Das Hauptskript fehlt:`n{0}"
    "start_rechte_meldung"   = "Der Update-Manager braucht Administratorrechte.`n`nAm einfachsten über update-manager-gui.bat starten, die fragt die Rechte selbst ab."
    "bereitgestellt_von"     = "bereitgestellt von"
    "hardware_bekannt"       = "Hardware wird erkannt …"
    "hardware_fehler"        = "Hardware konnte nicht gelesen werden"
    "aufgabe_bekannt"        = "Aufgabenplanung wird gelesen …"
    "was_ist_neu"            = "Was ist neu?"
    "herunterladen"          = "Herunterladen"
    "neue_fassung_knopf"     = "Neue Version installieren"
    "spaeter"                = "Später"

    # Kacheln (Chip 49, David, 25.11.2026): Kacheln tragen Beschriftungen
    # statt laufender Statistik - "5 von 5" und die Zahl der Laeufe sind weg,
    # jetzt sagt jede Kachel, was sie ist. "Einstellungen" ersetzt "5 von 5".
    "ergebnis_zahl"          = "Anzahl"
    "updates_letzter_lauf"   = "Updates im letzten Lauf"
    "einstellungen_titel"    = "Einstellungen"
    "quellen_aktiv"          = "Quellen aktiv"
    "verlauf"                = "Verlauf"
    "dieser_sitzung"         = "dieser Sitzung"
    "protokoll"              = "Protokoll"
    "protokoll_zeitraum"     = "Sieben Tage"
    "einstellungen_umschalten" = "Einstellungen ein- oder ausblenden"
    "verlauf_umschalten"     = "Verlauf dieser Sitzung ein- oder ausblenden"
    "protokoll_umschalten"   = "Protokoll ein- oder ausblenden"
    "live_ausgabe"           = "Live-Ausgabe"

    # Ergebniskarte
    "wird_gelesen"           = "Wird gelesen …"
    "kein_protokoll"         = "Noch kein Protokoll vorhanden."
    "protokoll_lesen_fehler" = "Protokoll konnte nicht gelesen werden."
    "letzter_stiller_format" = "Letzter stiller Lauf: {0}"
    "es_gab_eins"            = "Es gab 1 Update, es wurde installiert."
    "es_gab_zahl_format"     = "Es gab {0} Updates, es wurden installiert."
    "fertig_nichts"          = "Fertig. Nichts war zu aktualisieren, oder alles war durch."
    "nach_minuten_format"    = "Nach {0} Minuten."
    "einzelheiten_details"   = "Einzelheiten unter Details."

    # Statuszeile waehrend eines Laufs
    "status_laeuft"           = "Läuft …"
    "status_sieht_nach"       = "Sieht nach …"
    "status_dauert"           = "Das dauert einige Minuten."
    "status_nichts_ausgewaehlt" = "Nichts ausgewählt."
    "status_fehlgeschlagen"   = "Fehlgeschlagen. Einzelheiten oben."
    "status_anzeige_gestoert_format" = "Anzeige gestört: {0}"
    "status_fehler_aufruf_format" = "[Fehler] {0} ist fehlgeschlagen: {1}"

    # Abschluss eines Laufs (Bilde-Abschluss)
    "fertig_minuten_format"     = "Fertig nach {0} Minuten."
    "fertig_protokoll_format"   = "Fertig nach {0} Minuten. Einzelheiten im Protokoll."
    "nachgesehen_sicher_eins"   = "Nachgesehen. Nichts verändert; 1 Sicherheitsupdate offen."
    "nachgesehen_sicher_zahl_format" = "Nachgesehen. Nichts verändert; {0} Sicherheitsupdates offen."
    "nachgesehen_ehrlich"       = "Nachgesehen. Nichts verändert."
    "mit_fehlern_beendet"       = "Mit Fehlern beendet"
    "auftrag_unbekannt"         = "Nicht gestartet: unbekannter Auftrag"
    "rechte_fehlen"             = "Nicht gestartet: Administratorrechte fehlen"
    "abgebrochen_code_format"   = "Abgebrochen (Code {0})"
    "nachsehen_unvollstaendig_format" = "Nachsehen unvollständig: {0}"
    "einzelheiten_im_protokoll" = "Einzelheiten im Protokoll."
    "abschluss_protokoll_format" = "{0} nach {1} Minuten (Code {2}). Einzelheiten über den Knopf Protokoll."

    # Aufgabenplanung
    "aufgabe_lesen_fehler"      = "Der Zustand der Aufgabenplanung ließ sich nicht lesen."
    "aufgabe_keine"             = "Kein nächtlicher Lauf eingerichtet. Uhrzeit setzen und Übernehmen drücken."
    "aufgabe_naechster_format"  = "Nächster Lauf: {0}"
    "aufgabe_zuletzt_format"    = "zuletzt {0}"
    "aufgabe_andere_fassung"    = "Achtung: Der nächtliche Lauf startet eine andere Fassung ({0}). Ein Klick auf Übernehmen hängt ihn auf diese Fassung um."
    "aufgabe_prio_format"       = "Läuft mit niedriger Priorität ({0}). Ein Klick auf Übernehmen stellt auf normal um."
    "zeit_format_fehler"        = "Uhrzeit bitte als HH:MM angeben, zum Beispiel 04:00."
    "zeit_wird_eingerichtet"    = "Wird eingerichtet …"
    "zeit_misslungen_format"    = "Hat nicht geklappt: {0}"
    "naechtlich"                = "Nächtlich um"
    "uhr"                       = "Uhr"
    "uebernehmen"               = "Übernehmen"

    # Quellen-Karte
    "was_pruefen"            = "Was soll geprüft und aktualisiert werden?"
    "schalter_winget"        = "Winget: Programme aus dem Microsoft-Paketverzeichnis"
    "schalter_choco"         = "Chocolatey: Programme aus dem Community-Verzeichnis"
    "schalter_windows"       = "Windows Update: System und Treiber"
    "schalter_store"         = "Microsoft Store: Apps im Hintergrund anstoßen"
    "schalter_treiber"       = "Hersteller-Werkzeuge: nur erkannte Hardware"
    "schalter_dauerhaft"     = "Diese Schalter bleiben gesetzt und gelten auch für den nächtlichen Lauf."

    # Selbst-Update-Karte
    "selbst_titel"           = "Selbst-Update"
    "schalter_selbst_pruefen" = "Nach neuer Fassung suchen (GitHub, höchstens einmal am Tag)"
    "selbst_ohne_signatur"   = "Installieren nach dem Laden bleibt ausgeschaltet, solange das Setup nicht signiert ist (CODE-SIGNING-POLICY.md). Der Manager zeigt dann nur den Hinweis auf eine neue Fassung."
    "sprache_label"          = "Sprache"
    "sprache_hinweis"        = "Die Wahl wird gespeichert und das Fenster für die neue Sprache neu geöffnet."
    "sprache_speichern_fehler" = "Einstellungen ließen sich nicht speichern: update-config.local.json ist beschädigt. Die Änderung gilt nur für diese Sitzung."

    # Statuszeile Selbst-Update
    "self_zeile_aus"         = "Selbst-Update: Prüfung auf neue Fassung ausgeschaltet (Einstellungen)."
    "self_zeile_aktuell_format" = "Selbst-Update: zuletzt {0} geprüft: Version {1} ist aktuell. Nichts wird von selbst installiert."
    "self_zeile_erreicht_nicht" = "Selbst-Update: Prüfung nicht erreichbar, erneut beim nächsten Start."
    "heute"                  = "heute"

    # Protokoll-Ansicht
    "filter_alles"           = "Alles"
    "filter_fehler_format"   = "Fehler ({0})"
    "keine_fehler_protokoll" = "Keine Fehler im Protokoll."
    "protokoll_leer"         = "Das Protokoll ist leer."
    "protokoll_anzeige_fehler_format" = "Protokoll konnte nicht angezeigt werden: {0}"
    "protokoll_bereit"       = "Bereit. Nichts wird verändert, bevor eine Schaltfläche gedrückt wird."

    # Tageskoepfe und Ergebniskarte aus protokoll-ansicht.ps1. Diese Sätze
    # standen dort fest eingebaut (deutsch) und zeigten im englischen Fenster
    # deutschen Wortlaut; seit dem 25.11.2026 liest die Ansicht sie von hier.
    "tageskopf_heute"           = "Heute"
    "tageskopf_gestern"         = "Gestern"
    "ergeb_gescheitert_lang"    = "Der letzte Lauf ist gescheitert. Er wird nachgeholt."
    "ergeb_install_eins"        = "Es gab 1 Update, erfolgreich installiert."
    "ergeb_installiert_format"  = "Es gab {0} Updates, alle erfolgreich installiert."
    "ergeb_teilweise_format"    = "{0} installiert, {1}. Einzelheiten unter Details."
    "ergeb_endete_format"       = "Der Lauf endete mit {0}. Einzelheiten unter Details."
    "ergeb_alles_aktuell"       = "Alles aktuell. Nichts zu tun."
    "fehler_zaehl_format"       = "{0} Fehler"

    # Zeile über den letzten stillen Lauf
    "noch_kein_stiller"      = "Noch kein stiller Lauf im Protokoll."
    "unbekannt"              = "unbekannt"
    "nichts_offen"           = "nichts offen"
    "gescheitert_vermerk"    = "gescheitert, wird nachgeholt"
    "fehler_im_protokoll_format" = "{0} Fehler im Protokoll"

    # Selbst-Update: Fassung und Installieren
    "fassung_verfuegbar_format" = "Version {0} ist verfügbar."
    "selbst_unsigniert_hinweis" = "Das Setup ist noch nicht signiert; Windows meldet evtl. einen unbekannten Herausgeber. Die Prüfsumme wird vor dem Start geprüft."
    "selbst_ja_installieren" = "Ja, installieren"
    "selbst_wird_geladen"    = "Wird geladen und installiert …"
    "selbst_nicht_installiert_format" = "Nicht installiert: {0}. Die bisherige Version bleibt."
    "selbst_keine_antwort"   = "keine Antwort"

    # Knopfreihe unten
    "schliessen"             = "Schließen"
    "nur_nachsehen"          = "Nur nachsehen"
    "aktualisieren"          = "Aktualisieren"
}

$script:GuiTabelleEn = @{
    # Header
    "kern_fehlt_format"      = "The main script is missing:`n{0}"
    "start_rechte_meldung"   = "The update manager needs administrator rights.`n`nEasiest is to start it via update-manager-gui.bat; that file asks for the rights itself."
    "bereitgestellt_von"     = "provided by"
    "hardware_bekannt"       = "Detecting hardware …"
    "hardware_fehler"        = "Could not read the hardware information"
    "aufgabe_bekannt"        = "Reading the scheduled task …"
    "was_ist_neu"            = "What's new?"
    "herunterladen"          = "Download"
    "neue_fassung_knopf"     = "Install new version"
    "spaeter"                = "Later"

    # Tiles (Chip 49, David, 25.11.2026): tiles carry captions instead of
    # running statistics - "3 of 5" and the number of runs are gone; each
    # tile says what it is. "Settings" takes the place of "3 of 5".
    "ergebnis_zahl"          = "Count"
    "updates_letzter_lauf"   = "Updates in the last run"
    "einstellungen_titel"    = "Settings"
    "quellen_aktiv"          = "sources active"
    "verlauf"                = "History"
    "dieser_sitzung"         = "this session"
    "protokoll"              = "Log"
    "protokoll_zeitraum"     = "Seven days"
    "einstellungen_umschalten" = "Show or hide the settings"
    "verlauf_umschalten"     = "Show or hide this session's history"
    "protokoll_umschalten"   = "Show or hide the log"
    "live_ausgabe"           = "Live output"

    # Result card
    "wird_gelesen"           = "Being read …"
    "kein_protokoll"         = "There is no log yet."
    "protokoll_lesen_fehler" = "The log could not be read."
    "letzter_stiller_format" = "Last silent run: {0}"
    "es_gab_eins"            = "There was 1 update, installed successfully."
    "es_gab_zahl_format"     = "There were {0} updates, installed successfully."
    "fertig_nichts"          = "Done. Nothing to update, or everything went through."
    "nach_minuten_format"    = "After {0} minutes."
    "einzelheiten_details"   = "Details under Details."

    # Status line during a run
    "status_laeuft"           = "Running …"
    "status_sieht_nach"       = "Checking …"
    "status_dauert"           = "This takes a few minutes."
    "status_nichts_ausgewaehlt" = "Nothing selected."
    "status_fehlgeschlagen"   = "Failed. Details above."
    "status_anzeige_gestoert_format" = "Display trouble: {0}"
    "status_fehler_aufruf_format" = "[Error] {0} failed: {1}"

    # End of a run (Bilde-Abschluss)
    "fertig_minuten_format"     = "Done after {0} minutes."
    "fertig_protokoll_format"   = "Done after {0} minutes. Details in the log."
    "nachgesehen_sicher_eins"   = "Checked. Nothing changed; 1 security update pending."
    "nachgesehen_sicher_zahl_format" = "Checked. Nothing changed; {0} security updates pending."
    "nachgesehen_ehrlich"       = "Checked. Nothing was changed."
    "mit_fehlern_beendet"       = "Finished with errors"
    "auftrag_unbekannt"         = "Not started: unknown task"
    "rechte_fehlen"             = "Not started: administrator rights missing"
    "abgebrochen_code_format"   = "Aborted (code {0})"
    "nachsehen_unvollstaendig_format" = "Check incomplete: {0}"
    "einzelheiten_im_protokoll" = "Details in the log."
    "abschluss_protokoll_format" = "{0} after {1} minutes (code {2}). Details via the Log button."

    # Scheduled task
    "aufgabe_lesen_fehler"      = "The scheduled task state could not be read."
    "aufgabe_keine"             = "No nightly run set up. Set a time and press Apply."
    "aufgabe_naechster_format"  = "Next run: {0}"
    "aufgabe_zuletzt_format"    = "last {0}"
    "aufgabe_andere_fassung"    = "Caution: the nightly run starts another version ({0}). Pressing Apply points it at this one."
    "aufgabe_prio_format"       = "Runs at low priority ({0}). Pressing Apply sets it back to normal."
    "zeit_format_fehler"        = "Enter the time as HH:MM, for example 04:00."
    "zeit_wird_eingerichtet"    = "Setting up …"
    "zeit_misslungen_format"    = "Did not work: {0}"
    "naechtlich"                = "Nightly at"
    "uhr"                       = "h"
    "uebernehmen"               = "Apply"

    # Sources card
    "was_pruefen"            = "What should be checked and updated?"
    "schalter_winget"        = "Winget: programs from the Microsoft package directory"
    "schalter_choco"         = "Chocolatey: programs from the community directory"
    "schalter_windows"       = "Windows Update: system and drivers"
    "schalter_store"         = "Microsoft Store: nudge apps in the background"
    "schalter_treiber"       = "Vendor tools: detected hardware only"
    "schalter_dauerhaft"     = "These toggles persist and also apply to the nightly run."

    # Self update card
    "selbst_titel"           = "Self update"
    "schalter_selbst_pruefen" = "Look for a new version (GitHub, at most once a day)"
    "selbst_ohne_signatur"   = "Installing after download stays off while the setup is unsigned (CODE-SIGNING-POLICY.md). The manager then only shows the notice of a new version."
    "sprache_label"          = "Language"
    "sprache_hinweis"        = "The choice is saved and the window opens again in the new language."
    "sprache_speichern_fehler" = "Settings could not be saved: update-config.local.json is damaged. The change applies to this session only."

    # Self update status line
    "self_zeile_aus"         = "Self update: the check for new versions is off (Settings)."
    "self_zeile_aktuell_format" = "Self update: last checked {0}, version {1} is current. Nothing installs on its own."
    "self_zeile_erreicht_nicht" = "Self update: the check did not reach GitHub, trying again at the next start."
    "heute"                  = "today"

    # Log view
    "filter_alles"           = "All"
    "filter_fehler_format"   = "Errors ({0})"
    "keine_fehler_protokoll" = "No errors in the log."
    "protokoll_leer"         = "The log is empty."
    "protokoll_anzeige_fehler_format" = "The log could not be shown: {0}"
    "protokoll_bereit"       = "Ready. Nothing changes until a button is pressed."

    # Day headers and result card from protokoll-ansicht.ps1 (see German
    # table above): these sentences used to be hardcoded German there and
    # showed up untranslated in the English window.
    "tageskopf_heute"           = "Today"
    "tageskopf_gestern"         = "Yesterday"
    "ergeb_gescheitert_lang"    = "The last run failed. It will be retried."
    "ergeb_install_eins"        = "There was 1 update, installed successfully."
    "ergeb_installiert_format"  = "There were {0} updates, all installed successfully."
    "ergeb_teilweise_format"    = "{0} installed, {1}. Details under Details."
    "ergeb_endete_format"       = "The run ended with {0}. Details under Details."
    "ergeb_alles_aktuell"       = "All up to date. Nothing to do."
    "fehler_zaehl_format"       = "{0} errors"

    # Line about the last silent run
    "noch_kein_stiller"      = "No silent run in the log yet."
    "unbekannt"              = "unknown"
    "nichts_offen"           = "nothing pending"
    "gescheitert_vermerk"    = "failed, will be retried"
    "fehler_im_protokoll_format" = "{0} errors in the log"

    # Self update: release and install
    "fassung_verfuegbar_format" = "Version {0} is available."
    "selbst_unsigniert_hinweis" = "The setup is not signed yet; Windows may report an unknown publisher. The checksum is verified before it starts."
    "selbst_ja_installieren" = "Yes, install"
    "selbst_wird_geladen"    = "Being downloaded and installed …"
    "selbst_nicht_installiert_format" = "Not installed: {0}. Your current version stays."
    "selbst_keine_antwort"   = "no answer"

    # Button row at the bottom
    "schliessen"             = "Close"
    "nur_nachsehen"          = "Check only"
    "aktualisieren"          = "Update"
}

function Get-GuiSprachTabelle {
    <#
        Eine Tabelle, ohne Rueckfall pro Schluessel: Die Probe verlangt, dass
        beide Tabellen vollstaendig gefuellt sind, also waere ein Rueckfall
        eine versteckte Luke. Unbekannter Code gilt als Deutsch.
    #>
    param([string]$Code)
    if ($Code -eq 'en') { return $script:GuiTabelleEn }
    return $script:GuiTabelleDe
}

function Lies-GuiKonfig {
    <#
        Die Werte, die das Fenster beim Start braucht, aus update-config.json
        und darueber (falls da) update-config.local.json. Fehlt alles, gelten
        die sicheren Vorgaben: Deutsch, alle Quellen an, Pruefung an.
        Treiber gilt als an, solange nicht ALLE Hersteller abgeschaltet sind.
    #>
    param([string]$Ordner)

    $r = [pscustomobject]@{
        Sprache = 'de'
        Pruefung = $true
        Quellen = @{ winget = $true; chocolatey = $true; windowsUpdate = $true
                     microsoftStore = $true; treiber = $true }
    }
    foreach ($name in 'update-config.json', 'update-config.local.json') {
        $pfad = Join-Path $Ordner $name
        if (-not (Test-Path -LiteralPath $pfad)) { continue }
        try {
            $k = Get-Content -LiteralPath $pfad -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { continue }

        $s = $k.PSObject.Properties['gui']
        if ($s -and $s.Value) {
            $w = $s.Value.PSObject.Properties['sprache']
            if ($w -and ($w.Value -eq 'de' -or $w.Value -eq 'en')) { $r.Sprache = $w.Value }
        }
        $a = $k.PSObject.Properties['selbstUpdate']
        if ($a -and $a.Value) {
            $w = $a.Value.PSObject.Properties['pruefen']
            if ($w -and $w.Value -is [bool]) { $r.Pruefung = $w.Value }
        }
        $q = $k.PSObject.Properties['updateSources']
        if ($q -and $q.Value) {
            foreach ($feld in 'winget', 'chocolatey', 'windowsUpdate', 'microsoftStore') {
                $v = $q.Value.PSObject.Properties[$feld]
                if ($v -and $v.Value) {
                    $w = $v.Value.PSObject.Properties['enabled']
                    if ($w -and $w.Value -is [bool]) { $r.Quellen[$feld] = $w.Value }
                }
            }
        }
        $h = $k.PSObject.Properties['hardwareVendors']
        if ($h -and $h.Value) {
            $werte = @()
            foreach ($feld in 'nvidia', 'amd', 'intel', 'msi') {
                $v = $h.Value.PSObject.Properties[$feld]
                if ($v -and $v.Value) {
                    $w = $v.Value.PSObject.Properties['enabled']
                    if ($w -and $w.Value -is [bool]) { $werte += $w.Value }
                }
            }
            if ($werte.Count -gt 0) { $r.Quellen['treiber'] = ($werte -contains $true) }
        }
    }
    return $r
}

function Schreibe-GuiKonfig {
    <#
        Traegt die Wahl des Fensters in update-config.local.json ein und
        fasst update-config.json NICHT an (gehoert zum Werkzeug). Andere
        Eigenschaften der lokalen Datei, auch ihre Kommentar-Felder, bleiben
        stehen. Eigene Datei unlesbar: nichts schreiben, $false zurueck,
        das Fenster sagt es statt es zu verschweigen.
    #>
    param(
        [string]$Ordner,
        [string]$Sprache,
        [bool]$Pruefung,
        $Quellen
    )
    try {
        $pfad = Join-Path $Ordner 'update-config.local.json'
        $lokal = $null
        if (Test-Path -LiteralPath $pfad) {
            try {
                $lokal = Get-Content -LiteralPath $pfad -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                return $false
            }
        }
        if ($null -eq $lokal) { $lokal = New-Object PSObject }

        foreach ($paar in @(
            @{ Abschnitt = 'gui'; Feld = 'sprache'; Wert = $Sprache },
            @{ Abschnitt = 'selbstUpdate'; Feld = 'pruefen'; Wert = $Pruefung }
        )) {
            $a = $lokal.PSObject.Properties[$paar.Abschnitt]
            if (-not $a -or $null -eq $a.Value) {
                $lokal | Add-Member -NotePropertyName $paar.Abschnitt -NotePropertyValue (New-Object PSObject)
                $a = $lokal.PSObject.Properties[$paar.Abschnitt]
            }
            $w = $a.Value.PSObject.Properties[$paar.Feld]
            if ($w) { $w.Value = $paar.Wert }
            else { $a.Value | Add-Member -NotePropertyName $paar.Feld -NotePropertyValue $paar.Wert }
        }

        $quellen = if ($Quellen) { $Quellen } else { @{} }
        $updateSources = Get-OderBaue-Abschnitt -Eltern $lokal -Name 'updateSources'
        foreach ($quelle in 'winget', 'chocolatey', 'windowsUpdate', 'microsoftStore') {
            # Ohne Angabe bleibt der bisherige Wert stehen (kein stiller Reset).
            $wert = if ($quellen.ContainsKey($quelle)) { [bool]$quellen[$quelle] } else { $null }
            $basis = Get-OderBaue-Abschnitt -Eltern $updateSources -Name $quelle
            if ($null -ne $wert) { Set-DauerhaftToggle -Abschnitt $basis -Feld 'enabled' -Wert $wert }
        }

        # Hersteller-Werkzeuge: ein Schalter im Fenster, vier Eintraege im Kern.
        if ($quellen.ContainsKey('treiber')) {
            $treiber = [bool]$quellen['treiber']
            $vendors = Get-OderBaue-Abschnitt -Eltern $lokal -Name 'hardwareVendors'
            foreach ($hersteller in 'nvidia', 'amd', 'intel', 'msi') {
                Set-DauerhaftToggle -Abschnitt (Get-OderBaue-Abschnitt -Eltern $vendors -Name $hersteller) -Feld 'enabled' -Wert $treiber
            }
        }

        [IO.File]::WriteAllText($pfad, ($lokal | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
        return $true
    } catch {
        return $false
    }
}

function Get-OderBaue-Abschnitt {
    # Ein Unterobjekt einer Konfiguration; ein vorhandenes bleibt wie es ist,
    # Kommentar-Felder inklusive.
    param($Eltern, [string]$Name)
    $a = $Eltern.PSObject.Properties[$Name]
    if ($a -and $a.Value) { return $a.Value }
    $neu = New-Object PSObject
    $Eltern | Add-Member -NotePropertyName $Name -NotePropertyValue $neu
    return $neu
}

function Set-DauerhaftToggle {
    # Ein Feld in einem existierenden Abschnitt setzen, ohne andere Felder
    # (etwa Kommentar-Felder) anzufassen.
    param($Abschnitt, [string]$Feld, $Wert)
    $w = $Abschnitt.PSObject.Properties[$Feld]
    if ($w) { $w.Value = $Wert }
    else { $Abschnitt | Add-Member -NotePropertyName $Feld -NotePropertyValue $Wert }
}

function Get-SelbstUpdateZeitpunkt {
    <#
        Der Zeitpunkt der letzten Selbst-Update-Pruefung, lesbar dargestellt,
        oder $null, wenn (noch) keiner da ist. Rein, ohne Dateizugriff.
    #>
    param($Zustand, [datetime]$Jetzt = (Get-Date), [string]$Sprache = 'de')
    try {
        if ($null -eq $Zustand) { return $null }
        $p = $Zustand.PSObject.Properties['geprueft']
        if (-not $p -or [string]::IsNullOrWhiteSpace("$($p.Value)")) { return $null }
        $wann = [datetime]::Parse("$($p.Value)", [Globalization.CultureInfo]::InvariantCulture,
                                  [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
        $beschriftung = if ($wann.Date -eq $Jetzt.Date) { Get-GuiSprachText 'heute' $Sprache } else { '{0:dd.MM.}' -f $wann }
        return '{0} {1:HH:mm}' -f $beschriftung, $wann
    } catch { return $null }
}

function Text-SelbstUpdateHinweis {
    <#
        Der Satz fuer die Statuszeile (Davids Wunsch, 25.11.2026): Sagt das
        Ergebnis der Tagespruefung UND, dass kein Installieren von selbst
        ablaeuft. Rein, die Probe kann ihn in beiden Sprachen abfragen.
    #>
    param([bool]$PruefenAn, [string]$Zeitpunkt, [bool]$NeueFassung, [string]$Version, [string]$Sprache = 'de')
    if (-not $PruefenAn) {
        return (Get-GuiSprachText 'self_zeile_aus' $Sprache)
    }
    if ($NeueFassung) {
        # Der Hinweis auf die Fassung steht in der eigenen Zeile darueber.
        return ''
    }
    if ([string]::IsNullOrWhiteSpace($Zeitpunkt)) {
        return (Get-GuiSprachText 'self_zeile_erreicht_nicht' $Sprache)
    }
    return (Get-GuiSprachText 'self_zeile_aktuell_format' $Sprache) -f $Zeitpunkt, $Version
}

function Get-GuiSprachText {
    # EIN Text aus der aktuellen Tabelle; eine stuemmige Suche in zwei
    # Tabellen statt einer globalen Variablen, damit die Probe den Code ohne
    # Zustand abrufen kann.
    param([string]$Schluessel, [string]$Code)
    $tabelle = Get-GuiSprachTabelle -Code $Code
    if ($tabelle.ContainsKey($Schluessel)) { return $tabelle[$Schluessel] }
    return ''
}

