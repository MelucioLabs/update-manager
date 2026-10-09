# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
.SYNOPSIS
    Universal Update Manager - Central update management for Windows

.DESCRIPTION
    Combines all update sources in one script:
    - Winget (Desktop Apps)
    - Chocolatey (Package Manager)
    - Windows Update (OS & Security)
    - Microsoft Store Apps
    - Hardware Vendor Tools (NVIDIA, AMD, Intel, MSI)

.NOTES
    Author:  David Vaupel (MelucioLabs)
    License: GPL-3.0-or-later, see LICENSE
#>

# KEIN `#Requires -RunAsAdministrator` (22.09.2026).
#
# Die Anweisung gilt fuer die GANZE Datei und sperrte damit auch das aus, was
# gar nichts aendert: `-AufgabeStatus` liest nur nach, wann der naechtliche
# Lauf faellig ist, und genau das braucht die Oberflaeche, bevor irgendjemand
# Rechte hat. Geprueft wird die Erhoehung deshalb unten zur Laufzeit, fuer
# alles ausser dieser einen Abfrage — dieselbe Berichtigung wie im Fenster.

param(
    [switch]$SilentMode,

    # Ein einzelner Auftrag ohne Menue und ohne Tastendruck. Dafuer da, dass
    # die Oberflaeche (update-manager-gui.ps1) dieselbe Arbeit anstossen kann
    # wie das Menue, statt sie ein zweites Mal zu beschreiben. Jede zweite
    # Fassung derselben Logik laeuft irgendwann auseinander - beim
    # Update-Manager ist das am 20.09.2026 schon einmal passiert.
    # Ein oder mehrere Namen, durch Komma getrennt: `-Auftrag winget,store`.
    # Das spart Wiederholung - Konfiguration, Voraussetzungen und
    # Hardware-Erkennung liefen sonst je Auftrag NEU, und im Protokoll stand
    # derselbe Block fuenfmal untereinander (Davids Befund 21.09.2026).
    #
    # EIN String, KEIN [string[]] mit ValidateSet, und das hat einen Grund:
    # `powershell.exe -File skript.ps1 -Auftrag winget,store` uebergibt den
    # Wert als EINEN String "winget,store". Ein ValidateSet auf [string[]]
    # prueft dann diesen ganzen String gegen die Liste und lehnt ab
    # ("gehoert nicht zu dem vom ValidateSet-Attribut angegebenen Satz").
    # Genau so gescheitert am 21.09.2026 beim ersten Start aus der
    # Oberflaeche. Geprueft wird deshalb unten von Hand, nach dem Zerlegen -
    # und die Meldung sagt dann auch, WELCHER Name nicht stimmt.
    [string]$Auftrag,

    # Nur nachsehen, nichts installieren. Gilt fuer 'pruefen'.
    [switch]$NurPruefen,

    # Gibt den Zustand der Aufgabenplanung als JSON aus und beendet sich.
    # Fuer die Oberflaeche: Sie soll anzeigen koennen, wann der naechtliche
    # Lauf faellig ist und ob die Aufgabe ueberhaupt auf DIESE Datei zeigt —
    # ohne dafuer das Menue nachzubauen. Lesen geht ohne erhoehte Sitzung.
    [switch]$AufgabeStatus,

    # Richtet die Aufgabenplanung auf diese Uhrzeit ein (HH:MM) und beendet
    # sich. Damit kann die Oberflaeche dasselbe wie Menuepunkt 8, und der
    # Umweg ueber das Konsolenmenue entfaellt (Davids Punkt 22.09.2026).
    # Eingetragen wird dabei IMMER der Pfad dieser Datei — wer die Zeit im
    # Fenster setzt, hat damit zugleich die Aufgabe auf die Fassung
    # umgehaengt, aus der er es tut.
    [string]$AufgabeZeit,

    # Oeffnet das Protokoll mit den neuesten Laeufen OBEN (Davids Wunsch
    # 08.10.2026: kein Scrollen nach unten). Die Datei selbst bleibt
    # chronologisch, weil andere Stellen sie so lesen (der Tagesmarker des
    # stillen Laufs, die Kuerzung nach Zeit); angezeigt wird eine Kopie.
    # Aendert nichts am System und braucht keine Rechte.
    [switch]$ProtokollAnzeigen
)

# Die erste Zeile, die laeuft: Von hier bis zum Start des Prozesses reicht
# der "Anlauf", den der stille Lauf ins Protokoll schreibt (Write-Anlauf).
$Global:SkriptBeginn = Get-Date

# ============================================
# VERSION
# ============================================
# Dieselbe Zahl steht in update-manager-gui.ps1. Der Release-Workflow
# (.github/workflows/release.yml) bricht ab, wenn der Tag v<Version> nicht zu
# BEIDEN Konstanten passt; das Setup bekommt sie von dort. Grundlage fuer das
# spaetere Selbst-Update (SELBST-UPDATE.md).
$UpdaterVersion = '3.2.0'

# ============================================
# ENCODING
# ============================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================
# SPRACHE / LANGUAGE
# ============================================

$UILang = (Get-Culture).TwoLetterISOLanguageName

$T = @{}

if ($UILang -eq "de") {
    # Deutsch
    $T = @{
        # Allgemein
        "yes_keys"              = @("j", "J", "y", "Y")
        "yes_no_prompt"         = "(J/N)"
        "press_enter"           = "Drücke Enter zum Fortfahren"
        "press_any_key"         = "Beliebige Taste zum Fortfahren..."
        "error_prefix"          = "FEHLER"
        "skipped"               = "Übersprungen"
        "available"             = "Verfügbar"
        "not_found"             = "Nicht gefunden"
        "connected"             = "Verbunden"
        "offline"               = "Offline"
        "enabled"               = "Aktiviert"
        "disabled"              = "Deaktiviert"
        "loaded"                = "Geladen"
        "not_loaded"            = "Nicht geladen (Standardeinstellungen)"
        "goodbye"               = "Auf Wiedersehen!"
        "invalid_choice"        = "Ungültige Auswahl!"
        "no_internet"           = "Keine Internetverbindung!"
        "internet_ok"           = "Internetverbindung OK"
        "checking_prereqs"      = "Prüfe Voraussetzungen..."
        "winget_available"      = "Winget verfügbar"
        "winget_not_found"      = "Winget nicht gefunden"
        "detecting_hardware"    = "Erkenne Hardware..."
        "config_loaded"         = "Konfiguration geladen"
        "config_error"          = "Fehler beim Laden der Konfiguration"
        "config_default"        = "Verwende Standardeinstellungen..."
        "config_missing"        = "Konfigurationsdatei nicht gefunden"

        # Menü
        "menu_title"            = "UNIVERSAL UPDATE MANAGER"
        "menu_1"                = "1.  Alle Updates (Vollständig)"
        "menu_2"                = "2.  Winget Updates"
        "menu_3"                = "3.  Chocolatey Updates"
        "menu_4"                = "4.  Windows Update"
        "menu_5"                = "5.  Microsoft Store Apps"
        "menu_6"                = "6.  Hersteller-Updates (NVIDIA/AMD/Intel/MSI)"
        "menu_7"                = "7.  Silent Mode (Winget + Choco, kein Fenster)"
        "menu_8"                = "8.  Automatische Updates einrichten"
        "menu_9"                = "9.  System-Info anzeigen"
        "menu_10"               = "L.  Log-Datei öffnen"
        "menu_0"                = "0.  Beenden"
        "menu_prompt"           = "Auswahl"

        # Winget
        "winget_title"          = "WINGET UPDATES"
        "winget_disabled"       = "Winget-Updates sind deaktiviert (Config)."
        "winget_not_installed"  = "Winget ist nicht installiert!"
        "winget_hint"           = "Hinweis: Winget ist auf Windows 11 vorinstalliert."
        "winget_hint2"          = "Alternativ: 'App Installer' im Microsoft Store installieren."
        "winget_starting"       = "Starte Winget Updates..."
        "winget_checking"       = "Prüfe auf Updates..."
        "winget_timeout"        = "Winget antwortet nicht (Timeout). Überspringe..."
        "winget_updates_found"  = "Updates verfügbar:"
        "winget_install_prompt" = "Updates installieren?"
        "winget_installing"     = "Installiere Updates..."
        "winget_done"           = "Winget Updates abgeschlossen!"
        "winget_none"           = "Keine Winget-Updates verfügbar."
        "winget_skipped"        = "Winget Updates übersprungen."
        "winget_error"          = "Fehler bei Winget Updates"
        "winget_teilfehler"     = "Winget hat nicht alles aktualisiert"
        "winget_userscope_hint" = "Benutzer-Pakete lassen sich nicht aus der Admin-Sitzung aktualisieren. Wird gleich ohne erhoehte Rechte nachgeholt:"
        "nutzerlauf_start"      = "Zweiter Lauf ohne erhoehte Rechte fuer die Benutzer-Pakete..."
        "nutzerlauf_fertig"     = "Benutzer-Pakete: Nachlauf beendet."
        "nutzerlauf_fehler"     = "Nachlauf fuer Benutzer-Pakete nicht moeglich"
        "nutzerlauf_hand"       = "Von Hand nachholen in einer NORMALEN PowerShell:"
        "nutzerlauf_offen"      = "Benutzer-Pakete: nicht aktualisiert"
        "nutzerlauf_id_ungueltig" = "Paket-ID nicht verwertbar, übersprungen"
        "winget_locked_hint"    = "Programm läuft gerade und kann sich nicht selbst ersetzen. Erst schließen, dann aktualisieren:"

        # Chocolatey
        "choco_title"           = "CHOCOLATEY UPDATES"
        "choco_disabled"        = "Chocolatey-Updates sind deaktiviert (Config)."
        "choco_not_installed"   = "Chocolatey ist nicht installiert!"
        "choco_install_hint"    = "Installation (PowerShell als Admin):"
        "choco_starting"        = "Starte Chocolatey Updates..."
        "choco_self_update"     = "Aktualisiere Chocolatey selbst..."
        "choco_checking"        = "Prüfe auf veraltete Pakete..."
        "choco_timeout"         = "Chocolatey antwortet nicht (Timeout). Überspringe..."
        "choco_install_prompt"  = "Pakete aktualisieren?"
        "choco_installing"      = "Aktualisiere Pakete..."
        "choco_done"            = "Chocolatey Updates abgeschlossen!"
        "choco_none"            = "Keine Chocolatey-Updates verfügbar."
        "choco_skipped"         = "Chocolatey Updates übersprungen."
        "choco_error"           = "Fehler bei Chocolatey Updates"
        "choco_teilfehler"      = "Chocolatey hat nicht alles aktualisiert"

        # Windows Update
        "wu_title"              = "WINDOWS UPDATE"
        "wu_disabled"           = "Windows-Updates sind deaktiviert (Config)."
        "wu_module_missing"     = "PSWindowsUpdate Modul ist nicht installiert!"
        "wu_ps_version"         = "Aktuelle PowerShell Version"
        "wu_ps7_hint"           = "Hinweis: PowerShell 7+ nutzt eigene Module (nicht kompatibel mit PS 5.1)"
        "wu_module_install"     = "Installation:"
        "wu_module_prompt"      = "Modul jetzt installieren?"
        "wu_module_hand"        = "Windows Update übersprungen: Das Modul PSWindowsUpdate fehlt und wird nicht ungefragt nachgeladen. Von Hand:"
        "wu_weitere"            = "Windows meldet weitere Updates, die hier nicht erscheinen und nicht installiert werden:"
        "wu_weitere_wo"         = "Funktions-, Vorschau- und optionale Updates: Einstellungen > Windows Update."
        "wu_weitere_unbekannt"  = "Ob Windows weitere (optionale) Updates anbietet, ließ sich nicht prüfen"
        "wu_module_installing"  = "Installiere PSWindowsUpdate Modul..."
        "wu_module_done"        = "Modul erfolgreich installiert!"
        "wu_module_error"       = "Fehler bei Installation"
        "wu_starting"           = "Starte Windows Updates..."
        "wu_searching"          = "Suche nach Windows-Updates..."
        "wu_timeout"            = "Windows Update antwortet nicht (Timeout). Überspringe..."
        "wu_found"              = "Gefundene Updates:"
        "wu_install_prompt"     = "Updates installieren?"
        "wu_installing"         = "Installiere Updates..."
        "wu_done"               = "Windows Updates abgeschlossen!"
        "wu_none"               = "Keine Windows-Updates verfügbar."
        "wu_skipped"            = "Windows Updates übersprungen."
        "wu_reboot"             = "HINWEIS: Neustart erforderlich!"
        "wu_error"              = "Fehler bei Windows Updates"

        # Microsoft Store
        "store_title"           = "MICROSOFT STORE APPS"
        "store_disabled"        = "Microsoft Store Updates sind deaktiviert (Config)."
        "store_opening"         = "Öffne Microsoft Store..."
        "store_opened"          = "Microsoft Store geöffnet!"
        "store_hint"            = "Bitte manuell auf 'Alle aktualisieren' klicken."
        "store_error"           = "Fehler beim Öffnen des Microsoft Store"
        "check_title"           = "WAS STEHT AN (nichts wird installiert)"
        "check_winget"          = "Winget:"
        "check_choco"           = "Chocolatey:"
        "check_found"           = "Paket(e) koennten aktualisiert werden."
        "check_none"            = "Alles aktuell."
        "check_windows"         = "Windows Update:"
        "store_scan_start"      = "Store-Updates werden im Hintergrund angestossen..."
        "store_scan_done"       = "Angestossen. Der Store laedt und installiert selbst weiter."
        "store_scan_hint"       = "Kein Fenster noetig. Was eine Kontoanmeldung braucht, bleibt liegen."
        "store_scan_missing"    = "Hintergrund-Weg nicht verfuegbar (MDM-Klasse fehlt) - oeffne stattdessen den Store."

        # NVIDIA
        "nvidia_title"          = "NVIDIA TREIBER-UPDATE"
        "nvidia_starting"       = "Starte NVIDIA App..."
        "nvidia_started"        = "NVIDIA App gestartet!"
        "nvidia_hint"           = "Prüfe auf Treiber-Updates unter 'Treiber'."
        "nvidia_gfe_starting"   = "Starte NVIDIA GeForce Experience..."
        "nvidia_gfe_started"    = "GeForce Experience gestartet!"
        "nvidia_gfe_hint"       = "Prüfe auf Treiber-Updates unter 'Treiber' > 'Nach Updates suchen'."
        "nvidia_not_found"      = "Weder NVIDIA App noch GeForce Experience gefunden."
        "nvidia_download"       = "Download NVIDIA App: https://www.nvidia.com/de-de/software/nvidia-app/"
        "nvidia_error"          = "Fehler bei NVIDIA-Update"

        # AMD
        "amd_title"             = "AMD RADEON SOFTWARE"
        "amd_starting"          = "Starte AMD Radeon Software..."
        "amd_started"           = "AMD Radeon Software gestartet!"
        "amd_hint"              = "Prüfe auf Treiber-Updates unter 'System' > 'Software & Treiber'."
        "amd_not_found"         = "AMD Radeon Software nicht gefunden."
        "amd_download"          = "Download: https://www.amd.com/de/support"
        "amd_error"             = "Fehler bei AMD-Update"

        # Intel
        "intel_title"           = "INTEL DRIVER & SUPPORT ASSISTANT"
        "intel_running"         = "Intel DSA läuft bereits (Tray-Icon prüfen)."
        "intel_starting"        = "Starte Intel DSA..."
        "intel_started"         = "Intel DSA gestartet (Tray-Icon prüfen)."
        "intel_not_found"       = "Intel DSA nicht gefunden."
        "intel_hint"            = "Hinweis: CPU-Treiber werden meist via Windows Update aktualisiert."
        "intel_download"        = "Download: https://www.intel.com/content/www/us/en/support/detect.html"
        "intel_error"           = "Fehler bei Intel-Update"

        # MSI
        "msi_title"             = "MSI CENTER / LIVE UPDATE"
        "msi_opening"           = "Öffne MSI Center..."
        "msi_opened"            = "MSI Center geöffnet!"
        "msi_hint"              = "Updates unter 'Support' > 'Live Update' prüfen."
        "msi_not_found"         = "MSI Center nicht gefunden."
        "msi_download"          = "Download: https://www.msi.com/Landing/msi-center"
        "msi_error"             = "Fehler bei MSI-Update"

        # Silent Mode
        "silent_already_ran"    = "Silent Mode heute bereits ausgeführt – übersprungen"
        "silent_started"        = "Silent Mode gestartet"
        "silent_done"           = "Silent Mode abgeschlossen. Dauer"
        "silent_failed"         = "Silent Mode mit Fehlern beendet, wird beim nächsten Auslöser nachgeholt. Dauer"
        "silent_errors"         = "Fehler aufgetreten"
        "silent_result"         = "Silent Mode abgeschlossen. Details im Log"
        "silent_winget_start"   = "Starte Winget Silent-Update..."
        "silent_winget_done"    = "Winget Silent-Update abgeschlossen"
        "silent_winget_timeout" = "Winget Timeout"
        "silent_winget_skip"    = "Winget nicht verfügbar - übersprungen"
        "silent_winget_off"     = "Winget in Config deaktiviert - übersprungen"
        "silent_choco_start"    = "Starte Chocolatey Silent-Update..."
        "silent_choco_done"     = "Chocolatey Silent-Update abgeschlossen"
        "silent_choco_timeout"  = "Chocolatey Timeout"
        "silent_choco_skip"     = "Chocolatey nicht verfügbar - übersprungen"
        "silent_choco_off"      = "Chocolatey in Config deaktiviert - übersprungen"
        "silent_winget_found"   = "Winget-Updates gefunden"
        "silent_updated"        = "Aktualisiert"
        "silent_no_updates"     = "Keine Updates verfuegbar"
        "silent_updates_word"   = "Updates"
        "silent_winget_pinned"      = "Angeheftete Pakete werden einzeln aktualisiert"
        "silent_winget_pinned_fail" = "Angeheftetes Paket konnte nicht aktualisiert werden"
        "silent_winget_none"    = "Winget hat nichts aktualisiert, offen geblieben"
        "silent_winget_rest"    = "Winget: nicht aktualisiert, bleibt offen"
        "silent_winget_liste_fehlt" = "Liste der Winget-Updates nicht abrufbar, Winget-Schritt übersprungen"

        # Task Scheduler
        "task_title"            = "AUTOMATISCHE UPDATES EINRICHTEN"
        "task_prompt_time"      = "Zu welcher Uhrzeit sollen Updates automatisch laufen?"
        "task_prompt_hint"      = "Empfehlung: Nachts z.B. 03:00 (Format: HH:MM)"
        "task_prompt_input"     = "Uhrzeit eingeben"
        "task_invalid_format"   = "Ungültige Uhrzeit! Bitte Format HH:MM verwenden."
        "task_invalid_time"     = "Ungültige Uhrzeit!"
        "config_local"          = "Eigene Einstellungen geladen"
        "config_local_error"    = "Eigene Einstellungen unlesbar, es gelten die mitgelieferten"
        "push_titel"            = "Update-Manager: Lauf mit Fehlern"
        "push_protokoll"        = "Protokoll"
        "push_ohne_adresse"     = "Benachrichtigung ist eingeschaltet, aber ohne Adresse - es geht nichts raus"
        "push_ohne_zugang"      = "Benachrichtigung ist eingeschaltet, aber die Zugangsdatei fehlt"
        "push_fehler"           = "Benachrichtigung fehlgeschlagen"
        "job_fehler"            = "Abfrage fehlgeschlagen"
        "job_grenze"            = "Zeitgrenze"
        "zeit_start"            = "Start dauerte"
        "zeit_rechenzeit"       = "Rechenzeit"
        "zeit_gesamt"           = "vergangen insgesamt"
        "zeit_ausgelastet"      = "der Rechner war ausgelastet"
        "anlauf"                = "Anlauf vom Prozessstart bis zum Skript"
        "anlauf_bis_hier"       = "bis hier weitere"
        "anlauf_prio"           = "Priorität"
        "anlauf_lang"           = "Der Rechner ist ausgelastet, Zeitgrenzen können reißen"
        "anlauf_frei"           = "frei"
        "task_prio_niedrig"     = "Der nächtliche Lauf ist mit niedriger Priorität eingetragen und kommt unter Last zu kurz. Uhrzeit im Fenster einmal neu übernehmen, dann läuft er mit normaler Priorität"
        "task_replacing"        = "Bestehender Task wird ersetzt..."
        "braucht_rechte"        = "Der Update-Manager braucht Administratorrechte."
        "braucht_rechte_wie"    = "Am einfachsten ueber universal-update-manager.bat starten - die fragt sie selbst ab."
        "task_braucht_rechte"   = "Die Aufgabenplanung laesst sich nur mit Administratorrechten aendern."
        "task_fremde_datei"     = "ACHTUNG: Die Aufgabenplanung startet eine ANDERE Datei als diese hier. Der naechtliche Lauf arbeitet also mit einem anderen Stand."
        "task_fremde_hier"      = "hier laeuft   "
        "task_fremde_dort"      = "Aufgabe startet"
        "task_fremde_hilfe"     = "Richtigstellen: Menuepunkt 'Aufgabenplanung' in DIESER Datei einmal durchlaufen (er traegt den eigenen Pfad ein)."
        "task_done"             = "Task erfolgreich eingerichtet!"
        "task_label_name"       = "Name   "
        "task_label_time"       = "Uhrzeit"
        "task_label_mode"       = "Modus  "
        "task_label_missed"     = "Verpasst"
        "task_mode_desc"        = "Silent (Winget + Chocolatey, kein Fenster)"
        "task_missed_desc"      = "Wird beim nächsten Start nachgeholt"
        "task_daily"            = "Uhr (täglich)"
        "task_error"            = "FEHLER beim Einrichten des Tasks"
        "task_current"          = "Aktueller Task"
        "task_no_task"          = "Kein Task eingerichtet"
        "task_next_run"         = "Nächste Ausführung"
        "task_last_run"         = "Letzte Ausführung"
        "task_last_run_none"    = "Noch nie ausgeführt"
        "task_status"           = "Status"
        "task_action_prompt"    = "Was möchtest du tun?"
        "task_action_update"    = "U - Uhrzeit ändern"
        "task_action_delete"    = "L - Task löschen"
        "task_action_back"      = "Zurück"
        "task_deleted"          = "Task erfolgreich gelöscht!"
        "task_delete_confirm"   = "Task wirklich löschen?"

        # System Info
        "sysinfo_title"         = "SYSTEM-INFORMATIONEN"
        "sysinfo_hardware"      = "Hardware:"
        "sysinfo_cpu"           = "  CPU"
        "sysinfo_gpu"           = "  GPU"
        "sysinfo_board"         = "  Mainboard"
        "sysinfo_sources"       = "Verfügbare Update-Quellen:"
        "sysinfo_winget"        = "  Winget"
        "sysinfo_choco"         = "  Chocolatey"
        "sysinfo_pswu"          = "  PSWindowsUpdate"
        "sysinfo_internet"      = "  Internet"
        "sysinfo_config"        = "Konfiguration:"
        "sysinfo_config_file"   = "  Config-Datei"
        "sysinfo_winget_cfg"    = "  Winget"
        "sysinfo_choco_cfg"     = "  Chocolatey"
        "sysinfo_wu_cfg"        = "  Windows Update"
        "sysinfo_store_cfg"     = "  Microsoft Store"

        # Zusammenfassung
        "summary_title"         = "ZUSAMMENFASSUNG"
        "summary_duration"      = "Dauer"
        "summary_minutes"       = "Minuten"
        "summary_checked"       = "Geprüft: Winget, Chocolatey, Windows Update, Store"
        "summary_nvidia"        = "GPU: NVIDIA App geöffnet"
        "summary_amd"           = "GPU: AMD Radeon Software geöffnet"
        "summary_intel"         = "CPU: Intel DSA geprüft"
        "summary_msi"           = "Mainboard: MSI Center geöffnet"
        "summary_log"           = "Log"
        "summary_done"          = "Vollständiges Update abgeschlossen!"

        # Log-Datei
        "log_not_found"         = "Log-Datei nicht gefunden!"
        "log_gekuerzt"          = "Protokoll gekürzt, entfernte Zeilen"
        "log_tage"              = "Tage werden aufgehoben"
        "log_altdatei"          = "Alte Protokolldatei entfernt"
        "log_pflege_fehler"     = "Protokoll ließ sich nicht kürzen"
        "log_ansicht_hinweis"   = "Ansicht: neueste Läufe oben, innerhalb eines Laufs der Reihe nach. Die Datei selbst bleibt unverändert."
        "log_neu_belegt"        = "ist ein Ordner oder ein Link und wird nicht angefasst"
        "log_started"           = "Update Manager gestartet"
        "log_stopped"           = "Update Manager beendet."
        "log_full_start"        = "Starte vollständiges Update..."
    }
} else {
    # English (Fallback)
    $T = @{
        # General
        "yes_keys"              = @("y", "Y")
        "yes_no_prompt"         = "(Y/N)"
        "press_enter"           = "Press Enter to continue"
        "press_any_key"         = "Press any key to continue..."
        "error_prefix"          = "ERROR"
        "skipped"               = "Skipped"
        "available"             = "Available"
        "not_found"             = "Not found"
        "connected"             = "Connected"
        "offline"               = "Offline"
        "enabled"               = "Enabled"
        "disabled"              = "Disabled"
        "loaded"                = "Loaded"
        "not_loaded"            = "Not loaded (using defaults)"
        "goodbye"               = "Goodbye!"
        "invalid_choice"        = "Invalid choice!"
        "no_internet"           = "No internet connection!"
        "internet_ok"           = "Internet connection OK"
        "checking_prereqs"      = "Checking prerequisites..."
        "winget_available"      = "Winget available"
        "winget_not_found"      = "Winget not found"
        "detecting_hardware"    = "Detecting hardware..."
        "config_loaded"         = "Configuration loaded"
        "config_error"          = "Error loading configuration"
        "config_default"        = "Using default settings..."
        "config_missing"        = "Configuration file not found"

        # Menu
        "menu_title"            = "UNIVERSAL UPDATE MANAGER"
        "menu_1"                = "1.  All Updates (Full)"
        "menu_2"                = "2.  Winget Updates"
        "menu_3"                = "3.  Chocolatey Updates"
        "menu_4"                = "4.  Windows Update"
        "menu_5"                = "5.  Microsoft Store Apps"
        "menu_6"                = "6.  Vendor Updates (NVIDIA/AMD/Intel/MSI)"
        "menu_7"                = "7.  Silent Mode (Winget + Choco, no window)"
        "menu_8"                = "8.  Set up automatic updates"
        "menu_9"                = "9.  Show system info"
        "menu_10"               = "L.  Open log file"
        "menu_0"                = "0.  Exit"
        "menu_prompt"           = "Choice"

        # Winget
        "winget_title"          = "WINGET UPDATES"
        "winget_disabled"       = "Winget updates are disabled (Config)."
        "winget_not_installed"  = "Winget is not installed!"
        "winget_hint"           = "Note: Winget is pre-installed on Windows 11."
        "winget_hint2"          = "Alternative: Install 'App Installer' from the Microsoft Store."
        "winget_starting"       = "Starting Winget updates..."
        "winget_checking"       = "Checking for updates..."
        "winget_timeout"        = "Winget not responding (timeout). Skipping..."
        "winget_updates_found"  = "Updates available:"
        "winget_install_prompt" = "Install updates?"
        "winget_installing"     = "Installing updates..."
        "winget_done"           = "Winget updates completed!"
        "winget_none"           = "No Winget updates available."
        "winget_skipped"        = "Winget updates skipped."
        "winget_error"          = "Error during Winget updates"
        "winget_teilfehler"     = "Winget did not update everything"
        "winget_userscope_hint" = "User-scope packages cannot be updated from the elevated session. Retrying without elevation:"
        "nutzerlauf_start"      = "Second pass without elevation for user-scope packages..."
        "nutzerlauf_fertig"     = "User-scope packages: second pass finished."
        "nutzerlauf_fehler"     = "Second pass for user-scope packages not possible"
        "nutzerlauf_hand"       = "Run manually in a NORMAL PowerShell:"
        "nutzerlauf_offen"      = "User packages: not updated"
        "nutzerlauf_id_ungueltig" = "Package ID not usable, skipped"
        "winget_locked_hint"    = "Program is currently running and cannot replace itself. Close it first, then update:"

        # Chocolatey
        "choco_title"           = "CHOCOLATEY UPDATES"
        "choco_disabled"        = "Chocolatey updates are disabled (Config)."
        "choco_not_installed"   = "Chocolatey is not installed!"
        "choco_install_hint"    = "Installation (PowerShell as Admin):"
        "choco_starting"        = "Starting Chocolatey updates..."
        "choco_self_update"     = "Updating Chocolatey itself..."
        "choco_checking"        = "Checking for outdated packages..."
        "choco_timeout"         = "Chocolatey not responding (timeout). Skipping..."
        "choco_install_prompt"  = "Update packages?"
        "choco_installing"      = "Updating packages..."
        "choco_done"            = "Chocolatey updates completed!"
        "choco_none"            = "No Chocolatey updates available."
        "choco_skipped"         = "Chocolatey updates skipped."
        "choco_error"           = "Error during Chocolatey updates"
        "choco_teilfehler"      = "Chocolatey did not update everything"

        # Windows Update
        "wu_title"              = "WINDOWS UPDATE"
        "wu_disabled"           = "Windows updates are disabled (Config)."
        "wu_module_missing"     = "PSWindowsUpdate module is not installed!"
        "wu_ps_version"         = "Current PowerShell version"
        "wu_ps7_hint"           = "Note: PowerShell 7+ uses its own modules (not compatible with PS 5.1)"
        "wu_module_install"     = "Installation:"
        "wu_module_prompt"      = "Install module now?"
        "wu_module_hand"        = "Windows Update skipped: the PSWindowsUpdate module is missing and is not installed without asking. Manually:"
        "wu_weitere"            = "Windows offers further updates that do not appear here and are not installed:"
        "wu_weitere_wo"         = "Feature, preview and optional updates: Settings > Windows Update."
        "wu_weitere_unbekannt"  = "Could not check whether Windows offers further (optional) updates"
        "wu_module_installing"  = "Installing PSWindowsUpdate module..."
        "wu_module_done"        = "Module installed successfully!"
        "wu_module_error"       = "Installation error"
        "wu_starting"           = "Starting Windows updates..."
        "wu_searching"          = "Searching for Windows updates..."
        "wu_timeout"            = "Windows Update not responding (timeout). Skipping..."
        "wu_found"              = "Updates found:"
        "wu_install_prompt"     = "Install updates?"
        "wu_installing"         = "Installing updates..."
        "wu_done"               = "Windows updates completed!"
        "wu_none"               = "No Windows updates available."
        "wu_skipped"            = "Windows updates skipped."
        "wu_reboot"             = "NOTE: Reboot required!"
        "wu_error"              = "Error during Windows updates"

        # Microsoft Store
        "store_title"           = "MICROSOFT STORE APPS"
        "store_disabled"        = "Microsoft Store updates are disabled (Config)."
        "store_opening"         = "Opening Microsoft Store..."
        "store_opened"          = "Microsoft Store opened!"
        "store_hint"            = "Please click 'Update all' manually."
        "store_error"           = "Error opening Microsoft Store"
        "check_title"           = "WHAT IS PENDING (nothing gets installed)"
        "check_winget"          = "Winget:"
        "check_choco"           = "Chocolatey:"
        "check_found"           = "package(s) could be updated."
        "check_none"            = "Everything up to date."
        "check_windows"         = "Windows Update:"
        "store_scan_start"      = "Triggering Store updates in the background..."
        "store_scan_done"       = "Triggered. The Store downloads and installs on its own."
        "store_scan_hint"       = "No window needed. Anything requiring a signed-in account stays pending."
        "store_scan_missing"    = "Background path unavailable (MDM class missing) - opening the Store instead."

        # NVIDIA
        "nvidia_title"          = "NVIDIA DRIVER UPDATE"
        "nvidia_starting"       = "Starting NVIDIA App..."
        "nvidia_started"        = "NVIDIA App launched!"
        "nvidia_hint"           = "Check for driver updates under 'Drivers'."
        "nvidia_gfe_starting"   = "Starting NVIDIA GeForce Experience..."
        "nvidia_gfe_started"    = "GeForce Experience launched!"
        "nvidia_gfe_hint"       = "Check for driver updates under 'Drivers' > 'Check for updates'."
        "nvidia_not_found"      = "Neither NVIDIA App nor GeForce Experience found."
        "nvidia_download"       = "Download NVIDIA App: https://www.nvidia.com/en-us/software/nvidia-app/"
        "nvidia_error"          = "Error during NVIDIA update"

        # AMD
        "amd_title"             = "AMD RADEON SOFTWARE"
        "amd_starting"          = "Starting AMD Radeon Software..."
        "amd_started"           = "AMD Radeon Software launched!"
        "amd_hint"              = "Check for driver updates under 'System' > 'Software & Drivers'."
        "amd_not_found"         = "AMD Radeon Software not found."
        "amd_download"          = "Download: https://www.amd.com/en/support"
        "amd_error"             = "Error during AMD update"

        # Intel
        "intel_title"           = "INTEL DRIVER & SUPPORT ASSISTANT"
        "intel_running"         = "Intel DSA is already running (check tray icon)."
        "intel_starting"        = "Starting Intel DSA..."
        "intel_started"         = "Intel DSA launched (check tray icon)."
        "intel_not_found"       = "Intel DSA not found."
        "intel_hint"            = "Note: CPU drivers are usually updated via Windows Update."
        "intel_download"        = "Download: https://www.intel.com/content/www/us/en/support/detect.html"
        "intel_error"           = "Error during Intel update"

        # MSI
        "msi_title"             = "MSI CENTER / LIVE UPDATE"
        "msi_opening"           = "Opening MSI Center..."
        "msi_opened"            = "MSI Center opened!"
        "msi_hint"              = "Check for updates under 'Support' > 'Live Update'."
        "msi_not_found"         = "MSI Center not found."
        "msi_download"          = "Download: https://www.msi.com/Landing/msi-center"
        "msi_error"             = "Error during MSI update"

        # Silent Mode
        "silent_already_ran"    = "Silent Mode already ran today - skipped"
        "silent_started"        = "Silent Mode started"
        "silent_done"           = "Silent Mode completed. Duration"
        "silent_failed"         = "Silent Mode finished with errors, will be retried on the next trigger. Duration"
        "silent_errors"         = "Errors occurred"
        "silent_result"         = "Silent Mode completed. Details in log"
        "silent_winget_start"   = "Starting Winget silent update..."
        "silent_winget_done"    = "Winget silent update completed"
        "silent_winget_timeout" = "Winget timeout"
        "silent_winget_skip"    = "Winget not available - skipped"
        "silent_winget_off"     = "Winget disabled in config - skipped"
        "silent_choco_start"    = "Starting Chocolatey silent update..."
        "silent_choco_done"     = "Chocolatey silent update completed"
        "silent_choco_timeout"  = "Chocolatey timeout"
        "silent_choco_skip"     = "Chocolatey not available - skipped"
        "silent_choco_off"      = "Chocolatey disabled in config - skipped"
        "silent_winget_found"   = "Winget updates found"
        "silent_updated"        = "Updated"
        "silent_no_updates"     = "No updates available"
        "silent_updates_word"   = "updates"
        "silent_winget_pinned"      = "Pinned packages will be updated individually"
        "silent_winget_pinned_fail" = "Pinned package could not be updated"
        "silent_winget_none"    = "Winget updated nothing, still pending"
        "silent_winget_rest"    = "Winget: not updated, still pending"
        "silent_winget_liste_fehlt" = "Could not query the list of Winget updates, Winget step skipped"

        # Task Scheduler
        "task_title"            = "SET UP AUTOMATIC UPDATES"
        "task_prompt_time"      = "At what time should updates run automatically?"
        "task_prompt_hint"      = "Recommendation: At night e.g. 03:00 (Format: HH:MM)"
        "task_prompt_input"     = "Enter time"
        "task_invalid_format"   = "Invalid time! Please use format HH:MM."
        "task_invalid_time"     = "Invalid time!"
        "config_local"          = "Local settings loaded"
        "config_local_error"    = "Local settings unreadable, using the shipped ones"
        "push_titel"            = "Update manager: run with errors"
        "push_protokoll"        = "Log"
        "push_ohne_adresse"     = "Notification is enabled but has no address - nothing is sent"
        "push_ohne_zugang"      = "Notification is enabled but the credentials file is missing"
        "push_fehler"           = "Notification failed"
        "job_fehler"            = "Query failed"
        "job_grenze"            = "time limit"
        "zeit_start"            = "start took"
        "zeit_rechenzeit"       = "CPU time"
        "zeit_gesamt"           = "elapsed in total"
        "zeit_ausgelastet"      = "the machine was under load"
        "anlauf"                = "Startup from process start to script"
        "anlauf_bis_hier"       = "until here another"
        "anlauf_prio"           = "priority"
        "anlauf_lang"           = "The machine is under load, time limits may be exceeded"
        "anlauf_frei"           = "free"
        "task_prio_niedrig"     = "The nightly run is registered with low priority and falls behind under load. Apply the time in the window once more, then it runs with normal priority"
        "task_replacing"        = "Replacing existing task..."
        "braucht_rechte"        = "The update manager needs administrator rights."
        "braucht_rechte_wie"    = "Easiest via universal-update-manager.bat - it asks for them itself."
        "task_braucht_rechte"   = "The scheduled task can only be changed with administrator rights."
        "task_fremde_datei"     = "WARNING: The scheduled task runs a DIFFERENT file than this one. The nightly run therefore uses a different version."
        "task_fremde_hier"      = "running here "
        "task_fremde_dort"      = "task starts   "
        "task_fremde_hilfe"     = "To fix: run the 'Scheduled task' menu entry from THIS file once (it registers its own path)."
        "task_done"             = "Task set up successfully!"
        "task_label_name"       = "Name   "
        "task_label_time"       = "Time   "
        "task_label_mode"       = "Mode   "
        "task_label_missed"     = "Missed "
        "task_mode_desc"        = "Silent (Winget + Chocolatey, no window)"
        "task_missed_desc"      = "Will run at next startup if missed"
        "task_daily"            = "o'clock (daily)"
        "task_error"            = "ERROR setting up task"
        "task_current"          = "Current Task"
        "task_no_task"          = "No task configured"
        "task_next_run"         = "Next run"
        "task_last_run"         = "Last run"
        "task_last_run_none"    = "Never run"
        "task_status"           = "Status"
        "task_action_prompt"    = "What do you want to do?"
        "task_action_update"    = "U - Change time"
        "task_action_delete"    = "D - Delete task"
        "task_action_back"      = "Go back"
        "task_deleted"          = "Task deleted successfully!"
        "task_delete_confirm"   = "Really delete task?"

        # System Info
        "sysinfo_title"         = "SYSTEM INFORMATION"
        "sysinfo_hardware"      = "Hardware:"
        "sysinfo_cpu"           = "  CPU"
        "sysinfo_gpu"           = "  GPU"
        "sysinfo_board"         = "  Mainboard"
        "sysinfo_sources"       = "Available update sources:"
        "sysinfo_winget"        = "  Winget"
        "sysinfo_choco"         = "  Chocolatey"
        "sysinfo_pswu"          = "  PSWindowsUpdate"
        "sysinfo_internet"      = "  Internet"
        "sysinfo_config"        = "Configuration:"
        "sysinfo_config_file"   = "  Config file"
        "sysinfo_winget_cfg"    = "  Winget"
        "sysinfo_choco_cfg"     = "  Chocolatey"
        "sysinfo_wu_cfg"        = "  Windows Update"
        "sysinfo_store_cfg"     = "  Microsoft Store"

        # Summary
        "summary_title"         = "SUMMARY"
        "summary_duration"      = "Duration"
        "summary_minutes"       = "minutes"
        "summary_checked"       = "Checked: Winget, Chocolatey, Windows Update, Store"
        "summary_nvidia"        = "GPU: NVIDIA App opened"
        "summary_amd"           = "GPU: AMD Radeon Software opened"
        "summary_intel"         = "CPU: Intel DSA checked"
        "summary_msi"           = "Mainboard: MSI Center opened"
        "summary_log"           = "Log"
        "summary_done"          = "Full update completed!"

        # Log file
        "log_not_found"         = "Log file not found!"
        "log_gekuerzt"          = "Log trimmed, lines removed"
        "log_tage"              = "days are kept"
        "log_altdatei"          = "Old log file removed"
        "log_pflege_fehler"     = "Could not trim the log"
        "log_ansicht_hinweis"   = "View: newest runs on top, in order within a run. The file itself is unchanged."
        "log_neu_belegt"        = "is a folder or a link and is left untouched"
        "log_started"           = "Update Manager started"
        "log_stopped"           = "Update Manager stopped."
        "log_full_start"        = "Starting full update..."
    }
}

# ============================================
# KONFIGURATION / CONFIGURATION
# ============================================

$ErrorActionPreference = "Continue"
# Ueber die Umgebungsvariable, nicht ueber den Laufwerksbuchstaben: Auf einer
# Maschine mit System auf D: oder umgelegtem ProgramData zeigte der feste Pfad
# ins Leere, und das Protokoll waere still verschwunden.
$LogDir    = Join-Path $env:ProgramData "UpdateManager"
$LogFile   = "$LogDir\universal-update-manager.log"
# Der Name der geplanten Aufgabe steht an mehreren Stellen; eine
# Umbenennung soll genau eine Zeile sein.
$AufgabeName     = "UpdateManager-SilentMode"
$ConfigFile      = "$PSScriptRoot\update-config.json"
# Die Fassung dieser Maschine. Gewinnt ueber die mitgelieferte, wird nicht
# versioniert (siehe Get-UpdateConfig).
$ConfigFileLocal = "$PSScriptRoot\update-config.local.json"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# Hier stand eine Rotation nach Groesse (ab 5 MB, drei Archive). Sie ist
# weg: Das Protokoll wird nach ZEIT gehalten, an einer Stelle
# (Invoke-LogPflege, aufgerufen im Startblock unten).

# Farben / Colors
$ColorSuccess = "Green"
$ColorError   = "Red"
$ColorWarning = "Yellow"
$ColorInfo    = "Cyan"
$ColorHeader  = "Magenta"

$Global:Config = $null
# Zaehlt die protokollierten Fehler dieses Laufs (siehe Get-LaufExitCode).
$Global:FehlerImLauf = 0

# ============================================
# LOGGING
# ============================================

function Repair-LogKodierung {
    # Die Altdatei einmalig von ANSI nach UTF-8 holen.
    #
    # Write-Log schrieb bis zum 21.09.2026 ohne -Encoding, und das ist in
    # Windows PowerShell 5.1 die ANSI-Codepage: "ü" steht dort als EIN Byte.
    # Ab jetzt wird UTF-8 geschrieben - ohne diese Umschreibung waere die
    # Datei danach gemischt, und gemischt kann kein Editor richtig anzeigen.
    #
    # Laeuft nur, wenn die Datei KEIN gueltiges UTF-8 ist; danach nie wieder,
    # weil die Pruefung dann zutrifft. Die alte Fassung bleibt als
    # .ansi-sicherung liegen: Ein Protokoll ist Beleg, und Belege wirft man
    # nicht beim Umkodieren weg. Weggeraeumt wird sie nach derselben Frist
    # wie die Zeilen des Protokolls selbst (Invoke-LogPflege, 7 Tage).
    param([string]$Pfad)

    if (-not (Test-Path $Pfad)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Pfad)
        if ($bytes.Length -eq 0) { return }

        $streng = New-Object System.Text.UTF8Encoding($false, $true)
        try {
            [void]$streng.GetString($bytes)
            return          # schon UTF-8, nichts zu tun
        } catch { }

        Copy-Item $Pfad "$Pfad.ansi-sicherung" -Force -ErrorAction Stop
        $text = [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
        [System.IO.File]::WriteAllText($Pfad, $text, (New-Object System.Text.UTF8Encoding $true))
    } catch {
        # Kein Grund, den Lauf abzubrechen: Ein schlecht kodiertes Protokoll
        # ist aergerlich, ein nicht laufendes Update-Werkzeug schlimmer.
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    # UTF-8, nicht die Windows-Vorgabe. Add-Content schreibt in Windows
    # PowerShell 5.1 sonst ANSI, und dann steht im Protokoll ein einzelnes
    # Byte fuer "ü" - jeder Editor, der UTF-8 erwartet, zeigt dort ein
    # Ersatzzeichen (nachgemessen 21.09.2026 an der echten Datei).
    try { Add-Content -Path $LogFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    # Jeder Fehler zaehlt fuer den Exit-Code des Laufs (Get-LaufExitCode).
    if ($Level -eq "ERROR") { $Global:FehlerImLauf = [int]$Global:FehlerImLauf + 1 }
    switch ($Level) {
        "SUCCESS" { Write-Host $Message -ForegroundColor $ColorSuccess }
        "ERROR"   { Write-Host $Message -ForegroundColor $ColorError }
        "WARNING" { Write-Host $Message -ForegroundColor $ColorWarning }
        "INFO"    { Write-Host $Message -ForegroundColor $ColorInfo }
        default   { Write-Host $Message }
    }
}

function Get-LaufExitCode {
    <#
        Der Exit-Code eines Auftragslaufs: 0 nur, wenn kein Fehler
        protokolliert wurde, sonst 5.

        WARUM (03.10.2026). Der Auftragsmodus endete bis dahin IMMER mit
        `exit 0`, und das Fenster meldete danach "Fertig" in Gruen — auch
        wenn winget nicht geantwortet hatte oder Chocolatey abgebrochen war.
        Gezaehlt wird an der einen Stelle, durch die ohnehin jeder Fehler
        geht (Write-Log mit "ERROR"), statt an jeder Fundstelle eine eigene
        Merkvariable zu pflegen: Die vergisst man beim naechsten Zweig.

        5 und nicht 1, damit das Fenster "gelaufen, aber mit Fehlern" von
        "abgebrochen" (1), "unbekannter Auftrag" (2) und "keine Rechte" (4)
        unterscheiden kann.
    #>
    if ([int]$Global:FehlerImLauf -gt 0) { return 5 }
    return 0
}

# ============================================
# KONFIGURATION LADEN / LOAD CONFIG
# ============================================

function Merge-Konfig {
    <#
        Legt die eigene Fassung ueber die mitgelieferte, Abschnitt fuer
        Abschnitt. Was lokal nicht genannt wird, bleibt wie geliefert.
    #>
    param($Basis, $Eigen)
    if ($null -eq $Eigen) { return $Basis }
    if ($null -eq $Basis) { return $Eigen }
    foreach ($feld in $Eigen.PSObject.Properties) {
        $vorhanden = $Basis.PSObject.Properties[$feld.Name]
        if ($vorhanden -and $vorhanden.Value -is [pscustomobject] -and $feld.Value -is [pscustomobject]) {
            $vorhanden.Value = Merge-Konfig $vorhanden.Value $feld.Value
        } elseif ($vorhanden) {
            $vorhanden.Value = $feld.Value
        } else {
            $Basis | Add-Member -NotePropertyName $feld.Name -NotePropertyValue $feld.Value
        }
    }
    return $Basis
}

function Get-UpdateConfig {
    <#
        Zwei Dateien, nicht eine (22.09.2026):

          update-config.json         gehoert zum Werkzeug, liegt im Repo
          update-config.local.json   gehoert der MASCHINE, wird nicht versioniert

        WARUM. Alles, was nur hier gilt, muss irgendwohin: Zeitgrenzen,
        abgeschaltete Quellen, die Adresse des eigenen Meldedienstes. Stand
        das in der mitgelieferten Datei, liess sich das Werkzeug nicht
        weitergeben, ohne vorher aufzuraeumen — und beim naechsten `git pull`
        waere die eigene Einstellung wieder weg. Die zweite Datei loest
        beides: Sie gewinnt, sie bleibt liegen, und im Repo steht sie nicht.
    #>
    $cfg = $null
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            Write-Log "$($T['config_loaded']): $ConfigFile" "SUCCESS"
        } catch {
            Write-Log "$($T['config_error']): $($_.Exception.Message)" "ERROR"
            Write-Log $T['config_default'] "WARNING"
            return $null
        }
    } else {
        Write-Log "$($T['config_missing']): $ConfigFile" "WARNING"
        Write-Log $T['config_default'] "WARNING"
        return $null
    }

    if (Test-Path $ConfigFileLocal) {
        try {
            $eigen = Get-Content $ConfigFileLocal -Raw | ConvertFrom-Json
            $cfg = Merge-Konfig $cfg $eigen
            Write-Log "$($T['config_local']): $ConfigFileLocal" "SUCCESS"
        } catch {
            # Eine kaputte eigene Datei wird GENANNT und nicht uebergangen:
            # Sonst laeuft der Manager mit Vorgaben weiter, und niemand
            # versteht, warum seine Einstellung nichts tut.
            Write-Log "$($T['config_local_error']): $($_.Exception.Message)" "ERROR"
        }
    }
    return $cfg
}

# ============================================
# HILFSFUNKTIONEN / HELPER FUNCTIONS
# ============================================

function Test-WingetAvailable {
    try { $null = Get-Command winget -ErrorAction Stop; return $true } catch { return $false }
}

function Test-ChocoAvailable {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    } catch {
        # ChocolateyInstall kennt den echten Ort; der ProgramData-Pfad ist nur
        # die uebliche Vorgabe und stimmt nicht auf jeder Maschine.
        $chocoHeim = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { Join-Path $env:ProgramData "chocolatey" }
        if (Test-Path (Join-Path $chocoHeim "choco.exe")) {
            $env:Path += ";" + (Join-Path $chocoHeim "bin")
            return $true
        }
        return $false
    }
}

function Test-InternetConnection {
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect("8.8.8.8", 53, $null, $null)
        $wait  = $async.AsyncWaitHandle.WaitOne(3000, $false)
        if ($wait) { $tcp.EndConnect($async); return $true }
        return $false
    } catch { return $false }
    finally { if ($tcp) { $tcp.Dispose() } }
}

function Test-PSWindowsUpdateModule {
    try { return ($null -ne (Get-Module -ListAvailable -Name PSWindowsUpdate)) } catch { return $false }
}

function Test-YesResponse {
    param([string]$Response)
    return $T['yes_keys'] -contains $Response
}

function Run-JobWithTimeout {
    <#
        Fuehrt einen Block in einem eigenen Job aus, mit Zeitgrenze.

        DREI AUSGAENGE, NICHT EINER (berichtigt 22.09.2026). Bis dahin gab
        diese Funktion in ALLEN Faellen `$null` zurueck: bei echter
        Zeitueberschreitung, bei einem Fehler im Job und bei einem Lauf, der
        einfach nichts zu melden hatte. Die Aufrufer konnten das nicht
        unterscheiden und nannten alles "Timeout".

        Im Protokoll stand deshalb 74-mal "Windows Update antwortet nicht
        (Timeout). Ueberspringe... (120 s)" — am 21.09.2026 gemessen lagen
        zwischen Start und dieser Meldung 15 Sekunden. Gewartet wurde also
        nie; gemeldet wurde trotzdem eine Zeitueberschreitung. Der haeufigste
        Fall dahinter ist der harmloseste: Windows hatte schlicht keine
        Updates. Der zweite ist ein Fehler, dessen Text weggeworfen wurde.

        Zurueck kommt jetzt ein Zustand mit Begruendung. Die Regel dahinter
        ist dieselbe wie bei den Pruefern auf den Servern: Wer nicht messen
        konnte, sagt WARUM, statt einen Grund zu erfinden.
    #>
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds)
    # UTF-8 Encoding explizit im Job-Prozess setzen, damit Umlaute korrekt uebertragen werden
    $wrapper = [scriptblock]::Create("[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$OutputEncoding = [System.Text.Encoding]::UTF8; $ScriptBlock")
    $beginn = Get-Date
    $job = Start-Job -ScriptBlock $wrapper
    $completed = Wait-Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Zustand  = 'zeit'
            Ausgabe  = $null
            Fehler   = $null
            Sekunden = [math]::Round(((Get-Date) - $beginn).TotalSeconds)
        }
    }
    # FEHLER LIEGEN AN ZWEI STELLEN, und die Probe hat genau das gefunden:
    # Ein `throw` im Job beendet ihn, sein Grund steht dann in
    # `JobStateInfo.Reason` und NICHT in der `Error`-Sammlung — die bleibt
    # leer. Wer nur dort nachsieht, haelt einen abgestuerzten Job fuer einen
    # Lauf ohne Ergebnis. Nicht abbrechende Fehler wiederum stehen NUR in der
    # Sammlung. Also beide lesen.
    $teile = @()
    $kind = $job.ChildJobs | Select-Object -First 1
    if ($kind) {
        if ($kind.JobStateInfo.State -eq 'Failed' -and $kind.JobStateInfo.Reason) {
            $teile += $kind.JobStateInfo.Reason.Message
        }
        if ($kind.Error -and $kind.Error.Count -gt 0) {
            $teile += ($kind.Error | ForEach-Object { $_.ToString() })
        }
    }
    $output = Receive-Job $job -ErrorAction SilentlyContinue
    $fehler = if ($teile.Count -gt 0) { ($teile | Select-Object -Unique) -join '; ' } else { $null }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $zustand = if ($fehler) { 'fehler' } elseif ($null -eq $output -or @($output).Count -eq 0) { 'leer' } else { 'ok' }
    return [pscustomobject]@{
        Zustand  = $zustand
        Ausgabe  = $output
        Fehler   = $fehler
        Sekunden = [math]::Round(((Get-Date) - $beginn).TotalSeconds)
    }
}

function Send-Meldung {
    <#
        Schickt eine Meldung an den eigenen ntfy-Dienst.

        WOFUER (22.09.2026, Davids Auftrag). Der naechtliche Lauf laeuft ohne
        Fenster. Scheitert er, steht das im Protokoll und sonst nirgends —
        und ein Protokoll liest niemand vorsorglich. Dieselbe Stille wie bei
        einem Dienst, der gruen aussieht und nichts tut.

        GEMELDET WIRD NUR, WAS STOERT. Ein Lauf, der drei Programme
        aktualisiert hat, ist kein Ereignis; eine Meldung dafuer wuerde dazu
        fuehren, dass die naechste ueberlesen wird.

        Die Zugangsdaten stehen NICHT hier und nicht in der Konfiguration im
        Repo, sondern in einer eigenen Datei (Vorgabe: .ntfy-auth im
        Benutzerordner, Inhalt `benutzer:passwort`). Fehlt sie, wird das
        GESAGT statt stillschweigend nichts zu tun.
    #>
    param([string]$Titel, [string]$Text, [int]$Prio = 4, [string]$Tags = 'warning,gear')

    # Ueber PSObject.Properties abfragen, nicht direkt: Eine Konfiguration
    # ohne diesen Abschnitt ist der Normalfall (aeltere Datei, fremde
    # Maschine), und unter `Set-StrictMode -Version Latest` wirft ein direkter
    # Zugriff dann statt `$null` zu liefern. Der Kern laeuft heute ohne
    # StrictMode — die Probe nicht, und sie hat es prompt gefunden.
    $b = $null
    if ($Global:Config -and $Global:Config.PSObject.Properties['benachrichtigung']) {
        $b = $Global:Config.benachrichtigung
    }
    if (-not $b -or -not $b.enabled) { return $false }

    $url = $b.url
    if (-not $url) { Write-Log $T['push_ohne_adresse'] "WARNING"; return $false }

    $datei = if ($b.authDatei) { [Environment]::ExpandEnvironmentVariables($b.authDatei) } else { Join-Path $env:USERPROFILE '.ntfy-auth' }
    if (-not (Test-Path $datei)) {
        Write-Log "$($T['push_ohne_zugang']): $datei" "WARNING"
        return $false
    }

    try {
        $zugang = (Get-Content $datei -Raw).Trim()
        $kopf = @{
            Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($zugang))
            Title         = $Titel
            Priority      = "$Prio"
            Tags          = $Tags
        }
        Invoke-RestMethod -Uri $url -Method Post -Headers $kopf -Body $Text -TimeoutSec 10 | Out-Null
        return $true
    } catch {
        # Eine misslungene Meldung darf den Lauf nicht kippen — aber sie
        # gehoert ins Protokoll, sonst haelt man Stille fuer Ruhe.
        Write-Log "$($T['push_fehler']): $($_.Exception.Message)" "WARNING"
        return $false
    }
}

function Lies-JobAusgabe {
    <#
        Macht aus dem Zustand eines Jobs entweder eine Ausgabe oder eine
        ehrliche Meldung. Gibt `$null` zurueck, wenn der Aufrufer abbrechen
        soll.

        "Leer" ist dabei ausdruecklich KEIN Abbruch: Eine Abfrage ohne
        Ergebnis heisst fast immer "nichts offen", und genau das haben die
        Aufrufer bisher als Zeitueberschreitung gemeldet.
    #>
    param($Ergebnis, [string]$ZeitText, [int]$Grenze)

    if ($null -eq $Ergebnis) { return $null }
    if ($Ergebnis.Zustand -eq 'zeit') {
        # FEHLER, keine Warnung (03.10.2026): Nach einer Zeitueberschreitung
        # wird der Schritt uebersprungen — die Arbeit ist also NICHT getan.
        # Als Warnung liess das den Lauf gruen enden.
        #
        # Die Grenze zaehlt erst, wenn der Job LAEUFT. Das Starten des Jobs
        # (ein eigener PowerShell-Prozess) kommt obendrauf und dauerte am
        # 03.10.2026 gut fuenf Minuten: Im Protokoll stand "Zeitgrenze: 60 s",
        # vergangen waren 380. Steht jetzt dabei, wenn es auffaellt.
        $gesamt = ""
        if ($Ergebnis.PSObject.Properties['Sekunden'] -and $Ergebnis.Sekunden -gt ($Grenze + 10)) {
            $gesamt = ", $($T['zeit_gesamt']) $($Ergebnis.Sekunden) s, $($T['zeit_ausgelastet'])"
        }
        Write-Log "$ZeitText ($($T['job_grenze']): $Grenze s$gesamt)" "ERROR"
        return $null
    }
    if ($Ergebnis.Zustand -eq 'fehler') {
        Write-Log "$($T['job_fehler']) ($($Ergebnis.Sekunden) s): $($Ergebnis.Fehler)" "ERROR"
        return $null
    }
    # DAS KOMMA IST NOETIG. PowerShell packt eine einelementige Liste beim
    # Zurueckgeben aus, und `@($null)` wird damit wieder zu `$null` — der
    # Aufrufer haette "nichts offen" erneut als Abbruch gelesen, also genau
    # den Fehler, den diese Funktion beseitigen soll. Auch das hat die Probe
    # gefunden und nicht der Verstand.
    $ausgabe = @($Ergebnis.Ausgabe | Where-Object { $null -ne $_ })
    return ,$ausgabe
}

function Invoke-ProcessWithTimeout {
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [int]$TimeoutSeconds = 300
    )
    try {
        # System.Diagnostics.Process direkt nutzen:
        # - CreateNoWindow=true: erzeugt versteckte Konsole (statt -NoNewWindow das eine existierende braucht)
        # - Async ReadToEndAsync(): verhindert Pipe-Buffer-Deadlocks bei grossem Output
        # - Funktioniert korrekt mit App Execution Aliases (winget) im Task Scheduler
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $ArgumentList
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        # Wie lange schon das STARTEN dauert, wird mitgemessen (03.10.2026).
        # Die Zeitgrenze unten zaehlt erst ab dem gestarteten Prozess; an den
        # fuenf Tagen mit "Chocolatey Timeout (90 s)" lagen zwischen "Starte
        # Chocolatey" und der Meldung aber 126 bis 238 Sekunden. Der Rest
        # steckte hier — und stand nirgends.
        $uhr = [System.Diagnostics.Stopwatch]::StartNew()
        $process.Start() | Out-Null
        $startSekunden = [math]::Round($uhr.Elapsed.TotalSeconds, 1)

        # Stdout/Stderr asynchron lesen (verhindert Deadlock wenn Buffer voll)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $exited = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $exited) {
            # Die verbrauchte Rechenzeit VOR dem Beenden lesen: Sie trennt
            # "hat gearbeitet und wurde nicht fertig" von "kam gar nicht zum
            # Zug". Am 03.10. hatte choco in 90 s nicht einmal seine erste
            # Protokollzeile geschrieben.
            $cpu = $null
            try { $cpu = [math]::Round($process.TotalProcessorTime.TotalSeconds, 1) } catch { }
            Stop-Prozessbaum -Prozess $process
            return @{ TimedOut = $true; Output = @(); ExitCode = -1; StartSeconds = $startSekunden; CpuSeconds = $cpu }
        }

        $stdout = $stdoutTask.Result
        $output = @()
        if ($stdout) { $output = @($stdout -split "`r?`n" | Where-Object { $_ -ne "" }) }
        return @{ TimedOut = $false; Output = $output; ExitCode = $process.ExitCode; StartSeconds = $startSekunden; CpuSeconds = $null }
    } catch {
        return @{ TimedOut = $false; Output = @("ERROR: $($_.Exception.Message)"); ExitCode = -1; StartSeconds = $null; CpuSeconds = $null }
    }
}

function Stop-Prozessbaum {
    <#
        Beendet einen Prozess MIT seinen Kindern.

        `Process.Kill()` trifft nur den einen Prozess (03.10.2026). winget
        und choco starten aber Installer; nach einer Zeitueberschreitung
        liefen die weiter, waehrend der Manager "abgebrochen" meldete und
        den naechsten Schritt begann — zwei Installationen nebeneinander.

        PowerShell 7 kann `Kill($true)`. Windows PowerShell 5.1 kennt die
        Ueberladung nicht; dort werden die Nachkommen selbst gesammelt.

        NICHT taskkill /T (Fund des Pruefers, 03.10.2026): Das geht allein
        nach der Eltern-PID, und Windows vergibt PIDs neu. Ein alter fremder
        Prozess, dessen laengst beendeter Elternprozess dieselbe Nummer
        trug, wuerde mitbeendet — und dieser Lauf ist erhoeht. Als Kind gilt
        deshalb nur, was NACH seinem Elternprozess gestartet wurde.
    #>
    param([System.Diagnostics.Process]$Prozess)
    if (-not $Prozess) { return }
    $erledigt = $false
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        try { $Prozess.Kill($true); $erledigt = $true } catch { }
    }
    if (-not $erledigt) {
        try {
            $alle = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)
            $wurzel = $alle | Where-Object { $_.ProcessId -eq $Prozess.Id } | Select-Object -First 1
            $baum = @()
            $offen = @($wurzel | Where-Object { $_ })
            while ($offen.Count -gt 0) {
                $naechste = @()
                foreach ($eltern in $offen) {
                    $kinder = @($alle | Where-Object {
                        $_.ParentProcessId -eq $eltern.ProcessId -and $_.ProcessId -ne $eltern.ProcessId -and
                        $_.CreationDate -and $eltern.CreationDate -and $_.CreationDate -ge $eltern.CreationDate
                    })
                    $baum += $kinder; $naechste += $kinder
                }
                $offen = $naechste
            }
            # Von unten nach oben, damit kein Kind seinen Elternprozess ueberlebt.
            [array]::Reverse($baum)
            foreach ($kind in $baum) { Stop-Process -Id $kind.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    try { if (-not $Prozess.HasExited) { $Prozess.Kill() } } catch { }
}

function Get-ZeitgrenzeHinweis {
    <#
        Was ueber eine Zeitueberschreitung GEMESSEN wurde, als Zusatz fuer
        die Meldung. Nur Zahlen und eine Deutung, die aus ihnen folgt: Hat
        schon das Starten des Prozesses lange gedauert, war der Rechner
        ausgelastet — die Grenze zu erhoehen, haette daran nichts geaendert.
    #>
    param($Ergebnis)
    if (-not $Ergebnis) { return "" }
    $teile = @()
    if ($null -ne $Ergebnis.StartSeconds) { $teile += "$($T['zeit_start']) $($Ergebnis.StartSeconds) s" }
    if ($null -ne $Ergebnis.CpuSeconds)   { $teile += "$($T['zeit_rechenzeit']) $($Ergebnis.CpuSeconds) s" }
    if ($null -ne $Ergebnis.StartSeconds -and $Ergebnis.StartSeconds -ge 10) { $teile += $T['zeit_ausgelastet'] }
    if ($teile.Count -eq 0) { return "" }
    return ", " + ($teile -join ", ")
}

function Show-SectionHeader {
    param([string]$Title)
    Write-Host "`n"
    Write-Host "============================================" -ForegroundColor $ColorHeader
    Write-Host $Title -ForegroundColor $ColorHeader
    Write-Host "============================================`n" -ForegroundColor $ColorHeader
}

function Read-SingleKey {
    param([string]$Prompt = "", [string]$Vorgabe = "j")

    # OHNE KONSOLE NICHT WARTEN (21.09.2026)
    #
    # Im Auftragsmodus laeuft dieses Skript als Kindprozess der Oberflaeche:
    # keine Tastatur, kein Fenster, umgeleitete Ausgabe. [Console]::ReadKey
    # wartet dort auf etwas, das nie kommt - das Fenster fror ein und Windows
    # schrieb "Keine Rueckmeldung" in den Titel. Die Frage IST beantwortet,
    # bevor der Prozess startet: Wer "Aktualisieren" drueckt, hat zugestimmt.
    if ($Global:OhneRueckfrage) {
        if ($Prompt) { Write-Host "$Prompt $Vorgabe (automatisch)" -ForegroundColor $ColorInfo }
        return $Vorgabe
    }
    if ($Prompt) { Write-Host "$Prompt " -NoNewline -ForegroundColor $ColorInfo }
    try {
        $key = [Console]::ReadKey($true)
    } catch {
        # Keine Konsole am anderen Ende. Lieber die Vorgabe als ein Haenger.
        Write-Host $Vorgabe
        return $Vorgabe
    }
    Write-Host $key.KeyChar
    return $key.KeyChar.ToString()
}

function Wait-AnyKey {
    param([string]$Prompt)
    # Im Auftragsmodus gibt es niemanden, der eine Taste druecken koennte.
    if ($Global:OhneRueckfrage) { return }
    if (-not $Prompt) { $Prompt = $T['press_any_key'] }
    Write-Host $Prompt -ForegroundColor $ColorInfo -NoNewline
    try { $null = [Console]::ReadKey($true) } catch { }
    Write-Host ""
}

# ============================================
# VORAUSSETZUNGEN / PREREQUISITES
# ============================================

function Test-Prerequisites {
    Write-Log $T['checking_prereqs'] "INFO"
    if (-not (Test-InternetConnection)) {
        Write-Log $T['no_internet'] "ERROR"
        return $false
    }
    Write-Log $T['internet_ok'] "SUCCESS"
    if (Test-WingetAvailable) {
        Write-Log $T['winget_available'] "SUCCESS"
    } else {
        Write-Log $T['winget_not_found'] "WARNING"
    }
    return $true
}

# ============================================
# HARDWARE-ERKENNUNG / HARDWARE DETECTION
# ============================================

function Get-HardwareInfo {
    Write-Log $T['detecting_hardware'] "INFO"
    $hw = @{ CPU = ""; GPU = ""; Mainboard = ""; HasNVIDIA = $false; HasAMD = $false; HasIntel = $false; HasMSI = $false }

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $hw.CPU = $cpu.Name
        $hw.HasIntel = $cpu.Name -like "*Intel*"
        Write-Log "CPU: $($hw.CPU)" "INFO"
    } catch {
        Write-Log "CPU detection error: $($_.Exception.Message)" "ERROR"
        $hw.CPU = "Unknown"
    }

    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
               Where-Object { $_.Name -notlike "*Microsoft*" } | Select-Object -First 1
        if ($gpu) {
            $hw.GPU = $gpu.Name
            $hw.HasNVIDIA = $gpu.Name -like "*NVIDIA*"
            $hw.HasAMD    = $gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*"
            Write-Log "GPU: $($hw.GPU)" "INFO"
        }
    } catch {
        Write-Log "GPU detection error: $($_.Exception.Message)" "ERROR"
        $hw.GPU = "Unknown"
    }

    try {
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop
        $hw.Mainboard = "$($board.Manufacturer) $($board.Product)"
        $hw.HasMSI = $board.Manufacturer -like "*Micro-Star*"
        Write-Log "Mainboard: $($hw.Mainboard)" "INFO"
    } catch {
        Write-Log "Mainboard detection error: $($_.Exception.Message)" "ERROR"
        $hw.Mainboard = "Unknown"
    }

    return $hw
}

# ============================================
# UPDATE-FUNKTIONEN / UPDATE FUNCTIONS
# ============================================

function Test-Erhoeht {
    try {
        $ich = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$ich).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Update-BenutzerPakete {
    <#
        Der zweite Lauf, ohne erhoehte Rechte.

        WARUM ES IHN GIBT (21.09.2026)
        Winget kann Pakete, die im BENUTZERBEREICH installiert sind, aus einer
        erhoehten Sitzung nicht aktualisieren ("user scope cannot be
        uninstalled"). Dieses Werkzeug laeuft aber immer erhoeht, weil Windows
        Update und Treiber das brauchen. Ergebnis: Ein Paket wie
        Stripe.StripeCli blieb auf ewig offen, und bei jedem Lauf stand
        dieselbe Warnung im Protokoll - Davids Befund.

        WIE
        Eine kurzlebige Aufgabe in der Aufgabenplanung, angelegt mit RunLevel
        "Limited" im Kontext des angemeldeten Nutzers. Das ist der
        zuverlaessige Weg, aus einem erhoehten Prozess einen UNerhoehten zu
        starten; runas und Verwandte scheitern daran regelmaessig. Die Aufgabe
        schreibt ihre Ausgabe in eine Datei, die hier eingelesen und ins
        Protokoll uebernommen wird, danach wird sie wieder entfernt.

        Laeuft die Sitzung ohnehin unerhoeht, wird direkt aktualisiert - dann
        braucht es den Umweg nicht.

        ZURUECK kommen die IDs, bei denen winget mit 0 endete (03.10.2026).
        Vorher kam nichts zurueck, und "Nachlauf beendet" stand auch dann in
        Gruen da, wenn kein einziges Paket aktualisiert wurde. Der stille
        Lauf braucht die Liste ausserdem, um zu wissen, was offen bleibt.
    #>
    param([string[]]$Ids)

    if (-not $Ids -or $Ids.Count -eq 0) { return @() }

    # Die IDs landen unten als Text in einem Skript. Was nicht wie eine
    # winget-ID aussieht, kommt dort nicht hinein — die Liste stammt aus
    # zerlegter Programmausgabe, nicht aus einer festen Tabelle.
    $liste = @($Ids | Select-Object -Unique | Where-Object { $_ -match '^[A-Za-z0-9][A-Za-z0-9._+-]*$' })
    $verworfen = @($Ids | Select-Object -Unique | Where-Object { $liste -notcontains $_ })
    if ($verworfen.Count -gt 0) {
        Write-Log "$($T['nutzerlauf_fehler']): $($T['nutzerlauf_id_ungueltig']) ($($verworfen.Count))" "WARNING"
    }
    if ($liste.Count -eq 0) { return @() }

    Write-Log $T['nutzerlauf_start'] "INFO"
    $erledigt = @()

    if (-not (Test-Erhoeht)) {
        # Kein Umweg noetig: Wir sind schon der Nutzer.
        foreach ($id in $liste) {
            & winget upgrade --id $id --exact --accept-source-agreements --accept-package-agreements --silent 2>&1 |
                ForEach-Object { Write-Host "   $_" }
            if ($LASTEXITCODE -eq 0) { $erledigt += $id }
        }
        Write-NutzerlaufErgebnis -Liste $liste -Erledigt $erledigt
        return $erledigt
    }

    # Ein Ordner je Lauf mit Zufallsnamen (03.10.2026, Fund des Pruefers):
    # Seit der stille Lauf den Nachlauf jede Nacht benutzt, waere ein fester
    # Name in %TEMP% eine Stelle, an der ein anderer Prozess die Ergebnisdatei
    # vorab hinlegen und "alles aktualisiert" behaupten koennte.
    $ordner  = Join-Path $env:TEMP ('UpdateManager-Nutzerlauf-' + [guid]::NewGuid().ToString('N'))
    $skript  = Join-Path $ordner 'nachlauf.ps1'
    $ausgabe = Join-Path $ordner 'nachlauf.txt'
    $aufgabe = 'UpdateManager-Benutzerpakete'

    try {
        New-Item -ItemType Directory -Force -Path $ordner -ErrorAction Stop | Out-Null
        Remove-Item $ausgabe -ErrorAction SilentlyContinue

        # Ein eigenes Skript statt einer langen -Command-Zeile: Quoten ueber
        # Aufgabenplanung, PowerShell und winget hinweg ist sonst eine
        # Fehlerquelle fuer sich.
        $zeilen = New-Object System.Collections.Generic.List[string]
        $zeilen.Add('[Console]::OutputEncoding = [System.Text.Encoding]::UTF8')
        foreach ($id in $liste) {
            $zeilen.Add("winget upgrade --id $id --exact --accept-source-agreements --accept-package-agreements --silent *>&1 | Out-File -FilePath `"$ausgabe`" -Append -Encoding utf8")
            # Je Paket eine Zeile mit dem Exit-Code: Nur daran laesst sich
            # hinterher sagen, WELCHES Paket durchging.
            $zeilen.Add("`"##EXIT $id `$LASTEXITCODE`" | Out-File -FilePath `"$ausgabe`" -Append -Encoding utf8")
        }
        $zeilen.Add("`"FERTIG`" | Out-File -FilePath `"$ausgabe`" -Append -Encoding utf8")
        [System.IO.File]::WriteAllText($skript, ($zeilen -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding $true))

        $aktion = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$skript`""
        $prinzipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $aufgabe -Action $aktion -Principal $prinzipal -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $aufgabe -ErrorAction Stop

        # Warten, bis die Aufgabe durch ist. Deckel bei 5 Minuten: Ein
        # haengender Nachlauf darf den Hauptlauf nicht festhalten.
        $grenze = (Get-Date).AddMinutes(5)
        $fertig = $false
        while ((Get-Date) -lt $grenze) {
            Start-Sleep -Seconds 2
            if (Test-Path $ausgabe) {
                $bisher = Get-Content $ausgabe -Raw -ErrorAction SilentlyContinue
                if ($bisher -and $bisher -match 'FERTIG') { $fertig = $true; break }
            }
        }

        if (Test-Path $ausgabe) {
            $gelesen = @(Get-Content $ausgabe -ErrorAction SilentlyContinue)
            $gelesen |
                Where-Object { $_.Trim() -and $_.Trim() -ne 'FERTIG' -and $_ -notmatch '^##EXIT ' } |
                ForEach-Object { Write-Host "   $_" }
            $erledigt = @(Get-NutzerlaufErledigt -Zeilen $gelesen)
        }
        if (-not $fertig) {
            Write-Log "$($T['nutzerlauf_fehler']) (Zeitueberschreitung)" "WARNING"
        }
        Write-NutzerlaufErgebnis -Liste $liste -Erledigt $erledigt
    } catch {
        Write-Log "$($T['nutzerlauf_fehler']): $($_.Exception.Message)" "WARNING"
        Write-Log "$($T['nutzerlauf_hand']) winget upgrade $($liste -join ' ')" "WARNING"
    } finally {
        Unregister-ScheduledTask -TaskName $aufgabe -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $skript -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ausgabe -ErrorAction SilentlyContinue
        # Erst die beiden Dateien, dann der leere Ordner: kein rekursives
        # Loeschen ueber eine Variable.
        Remove-Item -LiteralPath $ordner -ErrorAction SilentlyContinue
    }
    return $erledigt
}

function Get-NutzerlaufErledigt {
    <# Liest aus der Ausgabe des Nachlaufs die IDs, bei denen winget mit 0 endete. #>
    param([string[]]$Zeilen)
    $ok = @()
    foreach ($z in $Zeilen) {
        if ("$z" -match '^##EXIT (\S+) (-?\d+)\s*$' -and $Matches[2] -eq '0') { $ok += $Matches[1] }
    }
    return $ok
}

function Write-NutzerlaufErgebnis {
    <#
        Sagt, was der Nachlauf erreicht hat — und was nicht. "Beendet" in
        Gruen gibt es nur, wenn JEDES Paket durchging; sonst steht der
        fertige Befehl zum Nachholen von Hand im Protokoll.
    #>
    param([string[]]$Liste, [string[]]$Erledigt)
    $offen = @($Liste | Where-Object { $Erledigt -notcontains $_ })
    if ($offen.Count -eq 0) {
        Write-Log "$($T['nutzerlauf_fertig']) ($($Liste -join ', '))" "SUCCESS"
    } else {
        Write-Log "$($T['nutzerlauf_offen']): $($offen -join ', ')" "WARNING"
        Write-Log "$($T['nutzerlauf_hand']) winget upgrade $($offen -join ' ')" "WARNING"
    }
}

function Test-WingetBenutzerPaket {
    <#
        Ist das Paket im BENUTZERBEREICH installiert?

        Gefragt wird winget selbst, nicht die Fehlermeldung von `upgrade`:
        Deren Wortlaut haengt an Sprache und Fassung. `list --scope user`
        endet mit 0, wenn das Paket dort liegt, sonst mit 0x8A150014
        (nachgemessen 03.10.2026: stripe und Pandoc 0, Git und Chrome nicht).
    #>
    param([string]$Id)
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { return $false }
    $r = Invoke-ProcessWithTimeout -FilePath "winget.exe" `
        -ArgumentList "list --scope user --id $Id --exact --accept-source-agreements" -TimeoutSeconds 60
    return (-not $r.TimedOut -and $r.ExitCode -eq 0)
}

function Update-Winget {
    Show-SectionHeader $T['winget_title']

    if ($Global:Config -and -not $Global:Config.updateSources.winget.enabled) {
        Write-Log $T['winget_disabled'] "WARNING"
        return
    }

    if (-not (Test-WingetAvailable)) {
        Write-Log $T['winget_not_installed'] "ERROR"
        Write-Host $T['winget_hint'] -ForegroundColor $ColorInfo
        Write-Host "$($T['winget_hint2'])`n" -ForegroundColor $ColorInfo
        return
    }

    Write-Log $T['winget_starting'] "INFO"

    try {
        Write-Host $T['winget_checking'] -ForegroundColor $ColorInfo
        $timeout = if ($Global:Config -and $Global:Config.updateSources.winget.timeoutSeconds) { $Global:Config.updateSources.winget.timeoutSeconds } else { 90 }

        $result = Lies-JobAusgabe (Run-JobWithTimeout -ScriptBlock { winget upgrade 2>&1 } -TimeoutSeconds $timeout) $T['winget_timeout'] $timeout
        if ($null -eq $result) { return }

        $updates = $result | Where-Object { $_ -match "winget$" }

        if ($updates.Count -gt 0) {
            Write-Host "`n$($updates.Count) $($T['winget_updates_found'])`n" -ForegroundColor $ColorSuccess
            foreach ($line in $updates) {
                if ($line.Length -ge 44) { Write-Host "  - $($line.Substring(0,44).Trim())" -ForegroundColor White }
            }
            Write-Host ""

            $autoAccept = $Global:Config -and $Global:Config.updateSources.winget.autoAccept
            if (-not $autoAccept) {
                $r = Read-SingleKey "$($T['winget_install_prompt']) $($T['yes_no_prompt'])"
                if (-not (Test-YesResponse $r)) {
                    Write-Log $T['winget_skipped'] "WARNING"
                    return
                }
            }

            Write-Host "`n$($T['winget_installing'])`n" -ForegroundColor $ColorInfo
            # Ausgabe mitschneiden UND live anzeigen: die zwei bekannten
            # Fehlklassen (User-Scope in Admin-Sitzung, laufendes Programm)
            # scheitern sonst kryptisch und ohne Abhilfe-Hinweis (30.08.2026:
            # Pandoc/Stripe user-scope, Claude Code lief waehrend des Updates).
            $upgradeOutput = winget upgrade --all --accept-source-agreements --accept-package-agreements 2>&1 |
                ForEach-Object { Write-Host $_; $_ }
            # Sofort festhalten: Jeder weitere winget-Aufruf ueberschreibt ihn.
            $wingetExit = $LASTEXITCODE
            $nachlaufGestartet = $false
            $upgradeText = ($upgradeOutput | Out-String)

            # Fall 1: user-scope-Paket in erhoehter Sitzung -> IDs einsammeln
            # und den fertigen Befehl fuer die normale Shell ausgeben.
            if ($upgradeText -match 'user scope cannot be uninstalled') {
                $failedIds = @()
                $currentId = $null
                foreach ($line in $upgradeOutput) {
                    if ($line -match '\[([A-Za-z0-9][A-Za-z0-9.+-]*\.[A-Za-z0-9.+-]+)\]') { $currentId = $Matches[1] }
                    if ($line -match 'user scope cannot be uninstalled' -and $currentId) {
                        $failedIds += $currentId; $currentId = $null
                    }
                }
                Write-Host "`n$($T['winget_userscope_hint'])" -ForegroundColor $ColorWarning
                $idList = if ($failedIds.Count -gt 0) { $failedIds -join ' ' } else { '--all' }
                Write-Host "  winget upgrade $idList`n" -ForegroundColor White
                Write-Log "$($T['winget_userscope_hint']) $idList" "WARNING"

                # Und jetzt nicht nur sagen, sondern machen.
                if ($failedIds.Count -gt 0) {
                    $nachgeholt = @(Update-BenutzerPakete -Ids $failedIds)
                    # Nur wenn ALLE gescheiterten Pakete nachgeholt wurden,
                    # ist der Fehlercode von `--all` damit erledigt.
                    $nachlaufGestartet = ($nachgeholt.Count -ge @($failedIds | Select-Object -Unique).Count)
                }
            }

            # Fall 2: Binary in Benutzung (z.B. Claude Code aktualisiert sich,
            # waehrend eine Session laeuft) -> benennen statt nur 0x8a150003.
            if ($upgradeText -match 'Access is denied' -or $upgradeText -match 'Zugriff verweigert') {
                $lockedId = $null
                $lastSeenId = $null
                foreach ($line in $upgradeOutput) {
                    if ($line -match '\[([A-Za-z0-9][A-Za-z0-9.+-]*\.[A-Za-z0-9.+-]+)\]') { $lastSeenId = $Matches[1] }
                    if (($line -match 'Access is denied' -or $line -match 'Zugriff verweigert') -and $lastSeenId) { $lockedId = $lastSeenId }
                }
                Write-Host "`n$($T['winget_locked_hint'])" -ForegroundColor $ColorWarning
                Write-Host "  winget upgrade $(if ($lockedId) { $lockedId } else { '<Paket-ID>' })`n" -ForegroundColor White
                Write-Log "$($T['winget_locked_hint']) $lockedId" "WARNING"
                $nachlaufGestartet = $false     # gesperrt ist nicht nachgeholt
            }
            # winget sagt selbst, ob alles durchging (03.10.2026). Hier stand
            # bis dahin immer "abgeschlossen" in Gruen — auch bei
            # 0x8A15002C ("upgrade --all" mit Fehlschlaegen), dem Code, mit
            # dem der naechtliche Lauf 25-mal in Folge endete. Einzige
            # Ausnahme: Die Fehlschlaege waren Benutzer-Pakete, und der
            # Nachlauf ohne erhoehte Rechte hat sie ALLE aktualisiert.
            if ($wingetExit -ne 0 -and -not $nachlaufGestartet) {
                Write-Log ("$($T['winget_teilfehler']) (Exit: 0x{0:X8})" -f $wingetExit) "ERROR"
            } else {
                Write-Log $T['winget_done'] "SUCCESS"
            }
        } else {
            Write-Host "$($T['winget_none'])`n" -ForegroundColor $ColorSuccess
            Write-Log $T['winget_none'] "SUCCESS"
        }
    } catch {
        Write-Log "$($T['winget_error']): $($_.Exception.Message)" "ERROR"
    }
}

function Update-Chocolatey {
    Show-SectionHeader $T['choco_title']

    if ($Global:Config -and -not $Global:Config.updateSources.chocolatey.enabled) {
        Write-Log $T['choco_disabled'] "WARNING"
        return
    }

    if (-not (Test-ChocoAvailable)) {
        Write-Log $T['choco_not_installed'] "WARNING"
        Write-Host "$($T['choco_install_hint'])" -ForegroundColor $ColorInfo
        Write-Host "Set-ExecutionPolicy Bypass -Scope Process -Force" -ForegroundColor $ColorInfo
        Write-Host "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`n" -ForegroundColor $ColorInfo
        return
    }

    Write-Log $T['choco_starting'] "INFO"

    try {
        Write-Host "$($T['choco_self_update'])`n" -ForegroundColor $ColorInfo
        choco upgrade chocolatey -y

        Write-Host "`n$($T['choco_checking'])" -ForegroundColor $ColorInfo
        $timeout = if ($Global:Config -and $Global:Config.updateSources.chocolatey.timeoutSeconds) { $Global:Config.updateSources.chocolatey.timeoutSeconds } else { 90 }

        $result = Lies-JobAusgabe (Run-JobWithTimeout -ScriptBlock { choco outdated 2>&1 } -TimeoutSeconds $timeout) $T['choco_timeout'] $timeout
        if ($null -eq $result) { return }

        Write-Host ""
        Write-Host $result

        $packageLines = $result | Where-Object { $_ -match "^\S+\|" -and $_ -notmatch "^Output" }

        if ($packageLines.Count -gt 0) {
            $autoAccept = $Global:Config -and $Global:Config.updateSources.chocolatey.autoAccept
            if (-not $autoAccept) {
                Write-Host ""
                $r = Read-SingleKey "$($T['choco_install_prompt']) $($T['yes_no_prompt'])"
                if (-not (Test-YesResponse $r)) {
                    Write-Log $T['choco_skipped'] "WARNING"
                    return
                }
            }

            Write-Host "`n$($T['choco_installing'])`n" -ForegroundColor $ColorInfo
            choco upgrade all -y
            # 0 heisst gut; 1641 und 3010 heissen "gut, Neustart noetig".
            # Alles andere ist ein Fehlschlag und wurde bis zum 03.10.2026
            # trotzdem als "abgeschlossen" gemeldet.
            $chocoExit = $LASTEXITCODE
            if (@(0, 1641, 3010) -contains $chocoExit) {
                Write-Log $T['choco_done'] "SUCCESS"
            } else {
                Write-Log "$($T['choco_teilfehler']) (Exit: $chocoExit)" "ERROR"
            }
        } else {
            Write-Host "`n$($T['choco_none'])`n" -ForegroundColor $ColorSuccess
            Write-Log $T['choco_none'] "SUCCESS"
        }
    } catch {
        Write-Log "$($T['choco_error']): $($_.Exception.Message)" "ERROR"
    }
}

function Search-WindowsUpdateTitel {
    <#
        Fragt den Windows-Update-Dienst direkt (COM), ohne PSWindowsUpdate,
        und gibt die Titel zurueck — als Job-Ergebnis mit Zustand, wie
        Run-JobWithTimeout es liefert. Sucht nur, aendert nichts.
    #>
    param([switch]$Optional, [int]$TimeoutSeconds = 120)
    $kriterium = "IsInstalled=0 and IsHidden=0"
    if ($Optional) { $kriterium += " and DeploymentAction='OptionalInstallation'" }
    $block = [scriptblock]::Create(
        "`$sitzung = New-Object -ComObject Microsoft.Update.Session`n" +
        "`$fund = `$sitzung.CreateUpdateSearcher().Search(`"$kriterium`")`n" +
        "foreach (`$u in `$fund.Updates) { [string]`$u.Title }")
    return Run-JobWithTimeout -ScriptBlock $block -TimeoutSeconds $TimeoutSeconds
}

function Select-WeitereUpdates {
    <# Die angebotenen Titel, die in der bekannten Liste NICHT vorkommen. #>
    param([string[]]$Angeboten = @(), [string[]]$Bekannt = @())
    return @($Angeboten | Where-Object { $_ -and ($Bekannt -notcontains $_) } | Select-Object -Unique)
}

function Write-WindowsWeitereUpdates {
    <#
        Nennt die Updates, die Windows anbietet, die dieser Manager aber
        weder anzeigt noch installiert.

        WARUM (03.10.2026, Davids Befund: ein grosses Windows-Update, von dem
        der Manager nichts gesagt hatte). Nachgemessen am selben Tag: Die
        uebliche Suche — die von PSWindowsUpdate wie die eigene mit
        "IsInstalled=0" — liefert nur, was zur INSTALLATION freigegeben ist.
        Funktionsupdates ("Windows 11, version 26H2") und Vorschau-Updates
        gibt Windows als OPTIONALE Installation frei; sie erscheinen nur,
        wenn ausdruecklich mit DeploymentAction='OptionalInstallation'
        gesucht wird. Dieselbe Maschine, dieselbe Minute: Suche ohne den
        Zusatz 3 Treffer ohne 26H2, mit dem Zusatz stand es da.

        ANGEZEIGT, NICHT INSTALLIERT. Ein Funktionsupdate ist ein neues
        Betriebssystem mit mehreren Neustarts; das stoesst kein Werkzeug
        nebenher an. Der Manager sagt, dass es wartet und wo — die
        Entscheidung bleibt in den Windows-Einstellungen.

        Laesst sich die Frage nicht beantworten, steht auch DAS da, statt
        dass Schweigen als "nichts weiter" gelesen wird.
    #>
    param([string[]]$Bekannt = @(), [int]$TimeoutSeconds = 120)

    $erg = Search-WindowsUpdateTitel -Optional -TimeoutSeconds $TimeoutSeconds
    if ($null -eq $erg -or $erg.Zustand -eq 'zeit' -or $erg.Zustand -eq 'fehler') {
        $grund = if ($erg -and $erg.Fehler) { ": $($erg.Fehler)" } else { "" }
        Write-Log "$($T['wu_weitere_unbekannt'])$grund" "WARNING"
        return
    }
    $weitere = @(Select-WeitereUpdates -Angeboten @($erg.Ausgabe | ForEach-Object { "$_" }) -Bekannt $Bekannt)
    if ($weitere.Count -eq 0) { return }

    Write-Log "$($T['wu_weitere']) $($weitere -join '; ')" "WARNING"
    Write-Host "  $($T['wu_weitere_wo'])`n" -ForegroundColor $ColorInfo
}

function Update-Windows {
    Show-SectionHeader $T['wu_title']

    if ($Global:Config -and -not $Global:Config.updateSources.windowsUpdate.enabled) {
        Write-Log $T['wu_disabled'] "WARNING"
        return
    }

    if (-not (Test-PSWindowsUpdateModule)) {
        Write-Log $T['wu_module_missing'] "ERROR"

        $psVer = $PSVersionTable.PSVersion.Major
        Write-Host "$($T['wu_ps_version']): $psVer" -ForegroundColor $ColorInfo
        if ($psVer -ge 7) { Write-Host "$($T['wu_ps7_hint'])`n" -ForegroundColor $ColorWarning }

        Write-Host "$($T['wu_module_install'])" -ForegroundColor $ColorInfo
        Write-Host "Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser`n" -ForegroundColor $ColorInfo

        # VORGABE "NEIN" (03.10.2026). Ohne Tastatur — also aus dem Fenster —
        # beantwortete sich diese Frage bis dahin von selbst mit "j": Ein
        # Klick auf "Aktualisieren" lud ungefragt ein Modul aus der PSGallery
        # nach. Wer "Aktualisieren" drueckt, stimmt Updates zu, nicht der
        # Installation weiterer Software. Nachgeladen wird nur, wenn jemand
        # an der Konsole ausdruecklich "j" tippt; sonst steht der Befehl da.
        $r = Read-SingleKey "$($T['wu_module_prompt']) $($T['yes_no_prompt'])" -Vorgabe "n"
        if (Test-YesResponse $r) {
            try {
                Write-Host "`n$($T['wu_module_installing'])`n" -ForegroundColor $ColorInfo
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
                Write-Host "$($T['wu_module_done'])`n" -ForegroundColor $ColorSuccess
                Write-Log $T['wu_module_done'] "SUCCESS"
            } catch {
                Write-Host "$($T['wu_module_error']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
                Write-Log "$($T['wu_module_error']): $($_.Exception.Message)" "ERROR"
                return
            }
        } else {
            Write-Log "$($T['wu_module_hand']) Install-Module -Name PSWindowsUpdate -Scope CurrentUser" "WARNING"
            # Auch ohne das Modul laesst sich sagen, was Windows anbietet.
            Write-WindowsWeitereUpdates
            return
        }
    }

    Write-Log $T['wu_starting'] "INFO"

    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Host $T['wu_searching'] -ForegroundColor $ColorInfo

        $timeout = if ($Global:Config -and $Global:Config.updateSources.windowsUpdate.timeoutSeconds) { $Global:Config.updateSources.windowsUpdate.timeoutSeconds } else { 120 }

        $updates = Lies-JobAusgabe (Run-JobWithTimeout -ScriptBlock {
            Import-Module PSWindowsUpdate -ErrorAction Stop
            Get-WindowsUpdate -MicrosoftUpdate
        } -TimeoutSeconds $timeout) $T['wu_timeout'] $timeout
        if ($null -eq $updates) { return }

        Write-Host ""

        # Was Windows SONST noch anbietet (siehe Write-WindowsWeitereUpdates).
        # Vor der Meldung "keine Updates", damit sie nie allein dasteht, wenn
        # in den Einstellungen ein Funktionsupdate wartet.
        Write-WindowsWeitereUpdates -Bekannt @($updates | ForEach-Object { "$($_.Title)" }) -TimeoutSeconds $timeout

        if ($updates.Count -eq 0) {
            Write-Host "$($T['wu_none'])`n" -ForegroundColor $ColorSuccess
            Write-Log $T['wu_none'] "SUCCESS"
            return
        }

        Write-Host $T['wu_found'] -ForegroundColor $ColorInfo
        $updates | Format-Table -Property Title, Size

        Write-Host ""
        $r = Read-SingleKey "$($T['wu_install_prompt']) $($T['yes_no_prompt'])"
        if (Test-YesResponse $r) {
            Write-Host "`n$($T['wu_installing'])`n" -ForegroundColor $ColorInfo
            $includeDrivers = -not ($Global:Config -and $Global:Config.updateSources.windowsUpdate.includeDrivers -eq $false)
            if ($includeDrivers) {
                Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false
            } else {
                Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false -NotCategory "Drivers"
            }
            Write-Log $T['wu_done'] "SUCCESS"

            if (Get-WURebootStatus -Silent) {
                Write-Host "`n$($T['wu_reboot'])`n" -ForegroundColor $ColorWarning
                Write-Log $T['wu_reboot'] "WARNING"
            }
        } else {
            Write-Log $T['wu_skipped'] "WARNING"
        }
    } catch {
        Write-Log "$($T['wu_error']): $($_.Exception.Message)" "ERROR"
    }
}

function Update-MicrosoftStore {
    Show-SectionHeader $T['store_title']

    if ($Global:Config -and -not $Global:Config.updateSources.microsoftStore.enabled) {
        Write-Log $T['store_disabled'] "WARNING"
        return
    }

    # Erst der stille Weg, der Store bleibt zu.
    #
    # WARUM (21.09.2026, Davids Wunsch): Bisher sprang hier der Store auf und
    # wartete auf einen Klick. Das reisst den Lauf auseinander - im Silent Mode
    # waere es sogar ein Fenster, das nachts niemand sieht.
    #
    # Der MDM-Weg stoesst denselben Scan an, den der Store selbst benutzt, nur
    # ohne Oberflaeche. Die Klasse liegt in root\cimv2\mdm\dmmap und ist an
    # Administratorrechte gebunden - die hat dieses Skript ohnehin, die .bat
    # fordert sie beim Start an. Auf diesem Rechner nachgemessen: InstanceID
    # "AppManagement" vorhanden.
    #
    # GRENZE, die bewusst so bleibt: Store-Apps mit Kontobindung brauchen ein
    # angemeldetes Konto, und manche Installation greift erst beim naechsten
    # App-Start. Der Scan holt, was ohne Nachfrage geht; der Rest bleibt
    # liegen und wird auch so benannt, statt Vollzug zu melden.
    Write-Log $T['store_scan_start'] "INFO"

    $scanOk = $false
    try {
        $mdm = Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" `
            -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction Stop
        if ($mdm) {
            $null = $mdm | Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop
            $scanOk = $true
        }
    } catch {
        # Kein Abbruch: Fehlt die Klasse (Windows-Home, Richtlinie, keine
        # Erhoehung), bleibt der alte Weg. Ein Update-Schritt, der wegen des
        # bequemeren Weges GAR nichts tut, waere der schlechtere Tausch.
        Write-Log "$($T['store_scan_missing']) ($($_.Exception.Message))" "WARNING"
    }

    if ($scanOk) {
        Write-Host $T['store_scan_done'] -ForegroundColor $ColorSuccess
        Write-Host "$($T['store_scan_hint'])`n" -ForegroundColor $ColorInfo
        Write-Log $T['store_scan_done'] "SUCCESS"
        return
    }

    # Rueckfall: Store oeffnen wie bisher. Im Silent Mode waere ein Fenster
    # falsch - dort wird nur vermerkt, dass der stille Weg nicht ging.
    Write-Host "$($T['store_scan_missing'])`n" -ForegroundColor $ColorWarning
    if ($SilentMode) { return }

    Write-Log $T['store_opening'] "INFO"

    try {
        Write-Host "$($T['store_opening'])`n" -ForegroundColor $ColorInfo
        Start-Process "ms-windows-store://downloadsandupdates"
        Write-Host $T['store_opened'] -ForegroundColor $ColorSuccess
        Write-Host "$($T['store_hint'])`n" -ForegroundColor $ColorInfo
        Write-Log $T['store_opened'] "SUCCESS"
    } catch {
        Write-Log "$($T['store_error']): $($_.Exception.Message)" "ERROR"
        Write-Host "$($T['error_prefix']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
    }
}

function Update-NVIDIA {
    param($Hardware)
    if (-not $Hardware.HasNVIDIA) { return }
    if ($Global:Config -and -not $Global:Config.hardwareVendors.nvidia.enabled) { return }

    Show-SectionHeader $T['nvidia_title']
    Write-Log "Checking NVIDIA drivers..." "INFO"

    try {
        $nvidiaAppPaths = @(
            "C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe",
            "C:\Program Files (x86)\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe"
        )
        if ($Global:Config -and $Global:Config.hardwareVendors.nvidia.nvidiaAppPath) {
            $nvidiaAppPaths = @($Global:Config.hardwareVendors.nvidia.nvidiaAppPath) + $Global:Config.hardwareVendors.nvidia.nvidiaAppAlternativePaths
        }

        foreach ($path in $nvidiaAppPaths) {
            if (Test-Path $path) {
                Write-Host $T['nvidia_starting'] -ForegroundColor $ColorInfo
                Start-Process $path -ErrorAction SilentlyContinue
                Write-Host $T['nvidia_started'] -ForegroundColor $ColorSuccess
                Write-Host "$($T['nvidia_hint'])`n" -ForegroundColor $ColorInfo
                Write-Log "NVIDIA App launched: $path" "SUCCESS"
                return
            }
        }

        $gfePaths = @(
            "C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe",
            "C:\Program Files (x86)\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
        )
        if ($Global:Config -and $Global:Config.hardwareVendors.nvidia.geforceExperiencePath) {
            $gfePaths = @($Global:Config.hardwareVendors.nvidia.geforceExperiencePath) + $Global:Config.hardwareVendors.nvidia.alternativePaths
        }

        foreach ($path in $gfePaths) {
            if (Test-Path $path) {
                Write-Host $T['nvidia_gfe_starting'] -ForegroundColor $ColorInfo
                Start-Process $path -ErrorAction SilentlyContinue
                Write-Host $T['nvidia_gfe_started'] -ForegroundColor $ColorSuccess
                Write-Host "$($T['nvidia_gfe_hint'])`n" -ForegroundColor $ColorInfo
                Write-Log "GeForce Experience launched: $path" "SUCCESS"
                return
            }
        }

        Write-Host "$($T['nvidia_not_found'])`n" -ForegroundColor $ColorWarning
        Write-Host "$($T['nvidia_download'])`n" -ForegroundColor $ColorInfo
        Write-Log $T['nvidia_not_found'] "WARNING"
    } catch {
        Write-Log "$($T['nvidia_error']): $($_.Exception.Message)" "ERROR"
        Write-Host "$($T['error_prefix']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
    }
}

function Update-AMD {
    param($Hardware)
    if (-not $Hardware.HasAMD) { return }
    if ($Global:Config -and $Global:Config.hardwareVendors.amd -and -not $Global:Config.hardwareVendors.amd.enabled) { return }

    Show-SectionHeader $T['amd_title']
    Write-Log "Checking AMD drivers..." "INFO"

    try {
        $amdPaths = @(
            "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe",
            "$env:ProgramFiles\AMD\CNext\CNext\AMDRSServ.exe",
            "${env:ProgramFiles(x86)}\AMD\CNext\CNext\RadeonSoftware.exe"
        )
        if ($Global:Config -and $Global:Config.hardwareVendors.amd.radeonSoftwarePath) {
            $amdPaths = @($Global:Config.hardwareVendors.amd.radeonSoftwarePath) + $Global:Config.hardwareVendors.amd.alternativePaths
        }

        foreach ($path in $amdPaths) {
            if (Test-Path $path) {
                Write-Host $T['amd_starting'] -ForegroundColor $ColorInfo
                Start-Process $path -ErrorAction SilentlyContinue
                Write-Host $T['amd_started'] -ForegroundColor $ColorSuccess
                Write-Host "$($T['amd_hint'])`n" -ForegroundColor $ColorInfo
                Write-Log "AMD Radeon Software launched: $path" "SUCCESS"
                return
            }
        }

        Write-Host "$($T['amd_not_found'])`n" -ForegroundColor $ColorWarning
        Write-Host "$($T['amd_download'])`n" -ForegroundColor $ColorInfo
        Write-Log $T['amd_not_found'] "WARNING"
    } catch {
        Write-Log "$($T['amd_error']): $($_.Exception.Message)" "ERROR"
        Write-Host "$($T['error_prefix']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
    }
}

function Update-Intel {
    param($Hardware)
    if (-not $Hardware.HasIntel) { return }
    if ($Global:Config -and -not $Global:Config.hardwareVendors.intel.enabled) { return }

    Show-SectionHeader $T['intel_title']
    Write-Log "Checking Intel drivers..." "INFO"

    try {
        if (Get-Process | Where-Object { $_.ProcessName -like "*DSA*" }) {
            Write-Host "$($T['intel_running'])`n" -ForegroundColor $ColorSuccess
            Write-Log "Intel DSA already running" "SUCCESS"
            return
        }

        $intelPaths = @(
            "C:\Program Files (x86)\Intel\Driver and Support Assistant\DSATray.exe",
            "C:\Program Files (x86)\Intel\Driver and Support Assistant\x86\DSATray.exe",
            "C:\Program Files\Intel\Driver and Support Assistant\DSATray.exe"
        )
        if ($Global:Config -and $Global:Config.hardwareVendors.intel.dsaPath) {
            $intelPaths = @($Global:Config.hardwareVendors.intel.dsaPath) + $Global:Config.hardwareVendors.intel.alternativePaths
        }

        foreach ($path in $intelPaths) {
            if (Test-Path $path) {
                Write-Host $T['intel_starting'] -ForegroundColor $ColorInfo
                Start-Process $path -ErrorAction SilentlyContinue
                Write-Host "$($T['intel_started'])`n" -ForegroundColor $ColorSuccess
                Write-Log "Intel DSA launched: $path" "SUCCESS"
                return
            }
        }

        Write-Host "$($T['intel_not_found'])`n" -ForegroundColor $ColorWarning
        Write-Host $T['intel_hint'] -ForegroundColor $ColorInfo
        Write-Host "$($T['intel_download'])`n" -ForegroundColor $ColorInfo
        Write-Log $T['intel_not_found'] "WARNING"
    } catch {
        Write-Log "$($T['intel_error']): $($_.Exception.Message)" "ERROR"
        Write-Host "$($T['error_prefix']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
    }
}

function Update-MSI {
    param($Hardware)
    if (-not $Hardware.HasMSI) { return }
    if ($Global:Config -and -not $Global:Config.hardwareVendors.msi.enabled) { return }

    Show-SectionHeader $T['msi_title']
    Write-Log "Checking MSI software..." "INFO"

    try {
        Write-Host $T['msi_opening'] -ForegroundColor $ColorInfo
        $app = Get-AppxPackage | Where-Object { $_.PackageFamilyName -like "*MSICenter*" }

        if ($app) {
            Start-Process "shell:AppsFolder\$($app.PackageFamilyName)!App"
            Write-Host $T['msi_opened'] -ForegroundColor $ColorSuccess
            Write-Host "$($T['msi_hint'])`n" -ForegroundColor $ColorInfo
            Write-Log $T['msi_opened'] "SUCCESS"
        } else {
            Write-Host "$($T['msi_not_found'])`n" -ForegroundColor $ColorWarning
            Write-Host "$($T['msi_download'])`n" -ForegroundColor $ColorInfo
            Write-Log $T['msi_not_found'] "WARNING"
        }
    } catch {
        Write-Log "$($T['msi_error']): $($_.Exception.Message)" "ERROR"
        Write-Host "$($T['error_prefix']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
    }
}

# ============================================
# SILENT MODE
# ============================================

function Get-AnlaufSekunden {
    <# Sekunden zwischen dem Start des Prozesses und der ersten Zeile dieses Skripts. #>
    try {
        return [math]::Round(($Global:SkriptBeginn - (Get-Process -Id $PID).StartTime).TotalSeconds, 1)
    } catch { return $null }
}

function Test-AnlaufLang {
    <# Ab wann der Anlauf als Zeichen eines ausgelasteten Rechners gilt. #>
    param($Sekunden)
    return ($null -ne $Sekunden -and $Sekunden -ge 30)
}

function Write-Anlauf {
    <#
        Schreibt ins Protokoll, wie lange der Lauf zum ANLAUFEN gebraucht hat
        und mit welcher Prioritaet er laeuft.

        WARUM (03.10.2026). "Chocolatey Timeout (90 s)" stand in 5 von 44
        Laeufen im Protokoll, und die Erklaerung dazu war "der Laptop
        schlaeft". Nachgemessen stimmt das nicht: Der Rechner laeuft durch,
        in den Ereignissen steht an keinem der fuenf Tage ein Standby. Was
        die fuenf Tage gemeinsam haben, ist etwas anderes — ALLES war
        langsam. Zwei aufeinanderfolgende Protokollzeilen ohne Arbeit
        dazwischen lagen bis zu 19 Sekunden auseinander; am 03.10. kam die
        erste Zeile sieben Minuten nach dem Start der Aufgabe, und choco
        hatte in seinen 90 Sekunden nicht einmal die eigene erste
        Protokollzeile geschrieben. Chocolatey war nicht die Ursache,
        sondern das Letzte in der Reihe, das die Grenze riss.

        WAS den Rechner an diesen Tagen ausgebremst hat, liess sich
        nachtraeglich nicht mehr feststellen (kein Virenscan, kein Windows
        Update, kein Neustart in dem Zeitfenster). Deshalb misst der Lauf es
        ab jetzt selbst: Dauert der Anlauf lange, stehen Last und freier
        Speicher daneben. Die Zahl von 3 Sekunden an einem normalen Tag ist
        der Vergleichswert.

        Die Prioritaet steht dabei, weil sie ein Verdacht ist: Die
        Aufgabenplanung startet Aufgaben in der Vorgabe mit Prioritaet 7 —
        niedrigere Rechen-, Platten- und Speicherprioritaet. Solange nichts
        anderes laeuft, merkt man das nicht; unter Last kommt so ein Prozess
        als Letzter dran (siehe Register-UpdateTask).
    #>
    $anlauf = Get-AnlaufSekunden
    $prio = "?"
    try { $prio = "$((Get-Process -Id $PID).PriorityClass)" } catch { }
    $bisHier = [math]::Round(((Get-Date) - $Global:SkriptBeginn).TotalSeconds, 1)
    $zeile = "$($T['anlauf']): $anlauf s, $($T['anlauf_bis_hier']) $bisHier s, $($T['anlauf_prio']) $prio"

    if (-not (Test-AnlaufLang $anlauf)) {
        Write-Log $zeile "INFO"
        return
    }
    $last = "?"; $frei = "?"
    try { $last = [int]((Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average) } catch { }
    try { $frei = [int]((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1024) } catch { }
    Write-Log "$zeile. $($T['anlauf_lang']) (CPU $last %, RAM $($T['anlauf_frei']) $frei MB)" "WARNING"
}

function Invoke-SilentUpdate {
    # VOR dem Doppellauf-Schutz, damit die Meldung auch an einem Tag kommt,
    # an dem sonst nichts mehr passiert.
    Test-AufgabeZeigtHierher | Out-Null

    # Pruefen ob Silent Mode heute bereits erfolgreich gelaufen ist (sprachunabhaengiger Marker)
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if (Test-Path $LogFile) {
        $ranToday = Get-Content $LogFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match $today -and $_ -match "\[SILENT-DONE\]" } |
            Select-Object -First 1
        if ($ranToday) {
            Write-Log $T['silent_already_ran'] "INFO"
            return
        }
    }

    Write-Log "========================================" "INFO"
    Write-Log $T['silent_started'] "INFO"
    Write-Log "========================================" "INFO"
    Write-Anlauf

    $startTime = Get-Date
    $errors    = @()

    # --- Winget ---
    if ($Global:Config -and -not $Global:Config.updateSources.winget.enabled) {
        Write-Log $T['silent_winget_off'] "WARNING"
    } elseif (-not (Test-WingetAvailable)) {
        Write-Log $T['silent_winget_skip'] "WARNING"
    } else {
        Write-Log $T['silent_winget_start'] "INFO"
        try {
            $timeout = if ($Global:Config -and $Global:Config.updateSources.winget.timeoutSeconds) { $Global:Config.updateSources.winget.timeoutSeconds } else { 300 }

            # Schritt 1: Verfuegbare Updates auflisten (Listing via Start-Job ist OK)
            $listResult = Lies-JobAusgabe (Run-JobWithTimeout -ScriptBlock { winget upgrade --accept-source-agreements 2>&1 } -TimeoutSeconds 60) $T['winget_timeout'] 60
            $normalPackages = @()
            $pinnedPackages = @()

            # KEINE LISTE IST KEIN "NICHTS OFFEN" (03.10.2026).
            #
            # Lies-JobAusgabe gibt `$null` zurueck, wenn die Abfrage in die
            # Zeitgrenze lief oder scheiterte. Hier ging es damit einfach
            # weiter: null Pakete, also "Keine Updates verfuegbar" in Gruen.
            # So stand es am 03.10. um 04:18 im Protokoll — eine Zeile unter
            # "Winget antwortet nicht". Wer nicht nachsehen konnte, weiss
            # nicht, dass nichts ansteht.
            if ($null -eq $listResult) { throw $T['silent_winget_liste_fehlt'] }

            if ($listResult) {
                $listLines = @($listResult) | ForEach-Object { "$_" }
                $idStartPos = 0
                $verStartPos = 0
                $separatorFound = $false
                $inPinnedSection = $false

                foreach ($line in $listLines) {
                    # Angeheftete/Pinned-Sektion erkennen (DE: "explizite Zielgruppen...", EN: "explicit targeting")
                    if ($line -match "(?i)(explizit|explicit|angeheftet|pinned)") {
                        $inPinnedSection = $true
                        $separatorFound = $false
                        continue
                    }
                    # Header-Zeile parsen (case-insensitive, mit fuehrenden Leerzeichen)
                    if ($line -match "(?i)^\s*Name\s") {
                        $idMatch = [regex]::Match($line, "(?i)\bId\b")
                        $verMatch = [regex]::Match($line, "(?i)\bVersion\b")
                        if ($idMatch.Success) { $idStartPos = $idMatch.Index }
                        if ($verMatch.Success) { $verStartPos = $verMatch.Index }
                        continue
                    }
                    # Separator-Zeile (---...)
                    if ($line -match "^\s*-{5,}") {
                        $separatorFound = $true
                        continue
                    }
                    # Paketzeilen (nur nach Separator, enden mit "winget")
                    if ($separatorFound -and $line -match "\bwinget\s*$" -and $idStartPos -gt 0 -and $verStartPos -gt 0) {
                        if ($line -match "(?i)(fehler|error|failed|warning)") { continue }
                        $name = ""; $id = ""
                        if ($line.Length -gt $idStartPos) {
                            $name = $line.Substring(0, $idStartPos).Trim()
                        }
                        if ($line.Length -gt $verStartPos) {
                            $id = $line.Substring($idStartPos, $verStartPos - $idStartPos).Trim()
                        }
                        if ($name -and $id) {
                            $pkg = @{ Name = $name; Id = $id }
                            if ($inPinnedSection) { $pinnedPackages += $pkg }
                            else { $normalPackages += $pkg }
                        }
                    }
                }
            }

            $updatedNames = @()

            # Schritt 2a: Normale Pakete via --all aktualisieren
            if ($normalPackages.Count -gt 0) {
                $normalNames = $normalPackages | ForEach-Object { $_.Name }
                Write-Log "$($T['silent_winget_found']): $($normalNames -join ', ') ($($normalPackages.Count))" "INFO"

                $installResult = Invoke-ProcessWithTimeout -FilePath "winget.exe" `
                    -ArgumentList "upgrade --all --silent --accept-source-agreements --accept-package-agreements" `
                    -TimeoutSeconds $timeout

                if ($installResult.TimedOut) {
                    # ZAEHLT ALS FEHLER, nicht als Warnung (24.09.2026).
                    #
                    # In der Nacht auf den 24.09. lief genau das: winget wurde
                    # nach 300 s abgeschnitten, drei Pakete blieben offen — und
                    # weil eine Zeitueberschreitung nur eine Warnung war, kam
                    # keine Meldung. Ein Lauf, der fuenf Minuten haengt und
                    # nichts aktualisiert, ist aber genau der Fall, fuer den die
                    # Meldung da ist. Stiller Stillstand ist schlimmer als ein
                    # lauter Fehler.
                    Write-Log "$($T['silent_winget_timeout']) --all ($timeout s$(Get-ZeitgrenzeHinweis $installResult))" "ERROR"
                    $errors += "Winget: $($T['silent_winget_timeout']) --all ($timeout s$(Get-ZeitgrenzeHinweis $installResult)), offen: $($normalNames -join ', ')"
                } else {
                    # Debug: Winget-Output loggen fuer Diagnose
                    $dbgLines = ($installResult.Output | Select-Object -First 5) -join " | "
                    Write-Log "Winget --all output ($($installResult.Output.Count) lines, Exit: $($installResult.ExitCode)): $dbgLines" "INFO"

                    # Output parsen: welche Pakete wurden tatsaechlich installiert?
                    $currentPkg = ""
                    foreach ($outLine in $installResult.Output) {
                        $outStr = "$outLine"
                        # "(1/2) Gefunden Claude Code [Anthropic.ClaudeCode] Version 2.1.55"
                        if ($outStr -match "(?i)\(\d+/\d+\)\s+(Gefunden|Found)\s+.+?\[(\S+)\]") {
                            $currentPkg = $matches[2]
                        }
                        if ($outStr -match "(?i)(erfolgreich installiert|successfully installed)" -and $currentPkg) {
                            $matched = $normalPackages | Where-Object { $_.Id -eq $currentPkg } | Select-Object -First 1
                            if ($matched) { $updatedNames += $matched.Name }
                            $currentPkg = ""
                        }
                    }
                }
            }

            # Schritt 2b: Angeheftete Pakete einzeln via --id aktualisieren
            if ($pinnedPackages.Count -gt 0) {
                $pinnedNames = $pinnedPackages | ForEach-Object { $_.Name }
                Write-Log "$($T['silent_winget_pinned']): $($pinnedNames -join ', ') ($($pinnedPackages.Count))" "INFO"

                foreach ($pkg in $pinnedPackages) {
                    if (-not $pkg.Id) { continue }
                    # Die ID stammt aus spaltenweise zerlegter Ausgabe und
                    # geht gleich in eine Argumentzeile: nur, was wie eine
                    # winget-ID aussieht.
                    if ($pkg.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
                        Write-Log "$($T['silent_winget_pinned_fail']): $($pkg.Name) ($($T['nutzerlauf_id_ungueltig']))" "WARNING"
                        continue
                    }

                    $pkgResult = Invoke-ProcessWithTimeout -FilePath "winget.exe" `
                        -ArgumentList "upgrade --id $($pkg.Id) --silent --accept-source-agreements --accept-package-agreements" `
                        -TimeoutSeconds $timeout

                    if ($pkgResult.TimedOut) {
                        # Wie oben: abgeschnitten ist nicht erledigt.
                        Write-Log "$($T['silent_winget_timeout']) $($pkg.Name) ($timeout s$(Get-ZeitgrenzeHinweis $pkgResult))" "ERROR"
                        $errors += "Winget: $($T['silent_winget_timeout']) $($pkg.Name) ($timeout s)"
                    } else {
                        # Debug: Output loggen
                        $dbgPkg = ($pkgResult.Output | Select-Object -First 3) -join " | "
                        Write-Log "Winget --id $($pkg.Id) output ($($pkgResult.Output.Count) lines, Exit: $($pkgResult.ExitCode)): $dbgPkg" "INFO"

                        $pkgInstalled = $false
                        foreach ($outLine in $pkgResult.Output) {
                            if ("$outLine" -match "(?i)(erfolgreich installiert|successfully installed)") {
                                $pkgInstalled = $true
                                break
                            }
                        }
                        if ($pkgInstalled) {
                            $updatedNames += $pkg.Name
                        } else {
                            Write-Log "$($T['silent_winget_pinned_fail']): $($pkg.Name) (Exit: $($pkgResult.ExitCode))" "WARNING"
                        }
                    }
                }
            }

            # Schritt 2c: Benutzer-Pakete ohne erhoehte Rechte nachholen.
            #
            # `upgrade --all` endete im stillen Lauf in 25 von 25 Faellen mit
            # -1978335188. Das ist 0x8A15002C, "upgrade --all mit
            # Fehlschlaegen": Der Lauf ist erhoeht, und winget kann Pakete
            # aus dem BENUTZERBEREICH aus einer erhoehten Sitzung nicht
            # ersetzen. stripe wurde so 35-mal gefunden und nie aktualisiert,
            # Pandoc 13-mal (nachgemessen 03.10.2026: beide liegen im
            # Benutzerbereich). Der Nachlauf dafuer existierte schon, wurde
            # aber nur aus dem Menue gerufen.
            #
            # Nachgeholt werden NUR Benutzer-Pakete. Ein Maschinen-Paket ohne
            # erhoehte Rechte zu aktualisieren, hiesse nachts eine
            # UAC-Rueckfrage auf einem Bildschirm, vor dem niemand sitzt.
            $wingetAbgebrochen = [bool]($installResult -and $installResult.TimedOut)
            $nachzuholen = @()
            if (-not $wingetAbgebrochen) {
                $nachzuholen = @($normalPackages + $pinnedPackages |
                    Where-Object { $_.Id -and ($updatedNames -notcontains $_.Name) } |
                    Where-Object { Test-WingetBenutzerPaket -Id $_.Id })
            }
            if ($nachzuholen.Count -gt 0) {
                $nachgeholt = @(Update-BenutzerPakete -Ids @($nachzuholen | ForEach-Object { $_.Id }))
                foreach ($pkg in $nachzuholen) {
                    if ($nachgeholt -contains $pkg.Id) { $updatedNames += $pkg.Name }
                }
            }

            # Ergebnis loggen
            if ($updatedNames.Count -gt 0) {
                Write-Log "$($T['silent_updated']): $($updatedNames -join ', ') ($($updatedNames.Count) $($T['silent_updates_word']))" "SUCCESS"
                # Was nach einem Teilerfolg UEBRIG bleibt, wurde bis zum
                # 03.10.2026 still verworfen: "Aktualisiert: A, B, C" stand
                # da, und dass D und E wieder nicht dran waren, stand
                # nirgends.
                $rest = @($normalPackages + $pinnedPackages | Where-Object { $updatedNames -notcontains $_.Name } | ForEach-Object { $_.Name })
                if ($rest.Count -gt 0) {
                    $exitRest = ""
                    if ($installResult -and -not $installResult.TimedOut) {
                        $exitRest = " (Winget-Exit: 0x{0:X8})" -f [int]$installResult.ExitCode
                    }
                    Write-Log "$($T['silent_winget_rest']): $($rest -join ', ')$exitRest" "WARNING"
                }
            } elseif ($normalPackages.Count -eq 0 -and $pinnedPackages.Count -eq 0) {
                Write-Log "$($T['silent_winget_done']) - $($T['silent_no_updates'])" "SUCCESS"
            } else {
                # Es WURDEN Pakete gefunden, aber keines meldete "erfolgreich
                # installiert". Hier stand frueher SUCCESS - deshalb hing
                # stripe vom 14.03.2026 bis zum 20.09.2026 jeden Tag im
                # Protokoll, ohne dass es auffiel. Ein Lauf, der nichts
                # erreicht hat, ist keine Erfolgsmeldung.
                $offen = @()
                $offen += $normalPackages | ForEach-Object { $_.Name }
                $offen += $pinnedPackages | ForEach-Object { $_.Name }
                $exitHinweis = ""
                if ($installResult -and -not $installResult.TimedOut) {
                    $exitHinweis = " (Winget-Exit: $($installResult.ExitCode))"
                }
                Write-Log "$($T['silent_winget_none']): $($offen -join ', ')$exitHinweis" "WARNING"
            }
        } catch {
            $errors += "Winget: $($_.Exception.Message)"
            Write-Log "Winget error: $($_.Exception.Message)" "ERROR"
        }
    }

    # --- Chocolatey ---
    if ($Global:Config -and -not $Global:Config.updateSources.chocolatey.enabled) {
        Write-Log $T['silent_choco_off'] "WARNING"
    } elseif (-not (Test-ChocoAvailable)) {
        Write-Log $T['silent_choco_skip'] "WARNING"
    } else {
        Write-Log $T['silent_choco_start'] "INFO"
        try {
            $timeout = if ($Global:Config -and $Global:Config.updateSources.chocolatey.timeoutSeconds) { $Global:Config.updateSources.chocolatey.timeoutSeconds } else { 90 }

            # Direkt via Start-Process ausfuehren (nicht Start-Job)
            $chocoResult = Invoke-ProcessWithTimeout -FilePath "choco.exe" `
                -ArgumentList "upgrade all -y" `
                -TimeoutSeconds $timeout

            if ($chocoResult.TimedOut) {
                # Dieselbe Regel wie bei winget: abgeschnitten ist nicht erledigt.
                Write-Log "$($T['silent_choco_timeout']) ($timeout s$(Get-ZeitgrenzeHinweis $chocoResult))" "ERROR"
                $errors += "Chocolatey: $($T['silent_choco_timeout']) ($timeout s$(Get-ZeitgrenzeHinweis $chocoResult))"
            } else {
                # Erfolgreich aktualisierte Pakete aus Output parsen
                $chocoUpdated = @()
                foreach ($line in $chocoResult.Output) {
                    if ($line -match "The upgrade of (\S+) was successful") {
                        $chocoUpdated += $matches[1]
                    }
                }
                if ($chocoUpdated.Count -gt 0) {
                    Write-Log "$($T['silent_updated']): $($chocoUpdated -join ', ') ($($chocoUpdated.Count) $($T['silent_updates_word']))" "SUCCESS"
                } else {
                    Write-Log "$($T['silent_choco_done']) - $($T['silent_no_updates'])" "SUCCESS"
                }
            }
        } catch {
            $errors += "Chocolatey: $($_.Exception.Message)"
            Write-Log "Chocolatey error: $($_.Exception.Message)" "ERROR"
        }
    }

    $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-Log "========================================" "INFO"
    # [SILENT-DONE] NUR OHNE FEHLER (03.10.2026).
    #
    # Die Marke ist das, woran der naechste Start erkennt, dass heute schon
    # ein Lauf war (siehe oben) — und dann nichts mehr tut. Sie stand bisher
    # auch unter einem gescheiterten Lauf. Der zweite Ausloeser der Aufgabe
    # (bei der Anmeldung) ist aber genau dafuer da, einen Lauf nachzuholen;
    # mit der Marke unter einem Fehlschlag holte er nie etwas nach.
    if ($errors.Count -eq 0) {
        Write-Log "[SILENT-DONE] $($T['silent_done']): $duration $($T['summary_minutes'])" "INFO"
    } else {
        Write-Log "[SILENT-FAILED] $($T['silent_failed']): $duration $($T['summary_minutes'])" "ERROR"
        Write-Log "$($T['silent_errors']): $($errors -join ', ')" "ERROR"
        # Erst jetzt melden, nicht bei jedem einzelnen Fehler: EINE Nachricht
        # je Lauf, mit allem drin. Wer drei Meldungen fuer einen Lauf bekommt,
        # schaltet sie ab.
        Send-Meldung -Titel "$($T['push_titel']) ($env:COMPUTERNAME)" `
                     -Text  ("$($errors -join ' | ')`n`n$($T['push_protokoll']): $LogFile") `
                     -Prio 4 -Tags 'warning,gear' | Out-Null
    }
    Write-Log "========================================" "INFO"
}

# ============================================
# TASK SCHEDULER
# ============================================

function Get-AufgabeInfo {
    <#
        Alles, was ueber den naechtlichen Lauf bekannt ist, in EINEM Objekt:
        ob er eingerichtet ist, auf welche Uhrzeit, auf welche Datei, ob das
        diese hier ist, und wann er das naechste Mal faellt.

        An einer Stelle, weil drei Aufrufer dasselbe wissen wollen: die
        Selbstpruefung beim Start, die Ausgabe fuer das Fenster
        (`-AufgabeStatus`) und das Menue. Lesen geht ohne erhoehte Sitzung —
        nur das Aendern braucht Rechte.
    #>
    $taskName = $AufgabeName
    $leer = [pscustomobject]@{
        eingerichtet = $false; zeit = $null; pfad = $null
        zeigtHierher = $true;  naechsterLauf = $null; letzterLauf = $null
        aufgabe = $taskName;   hier = $PSCommandPath
        prioritaet = $null
    }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) { return $leer }

    # Den Pfad aus `-File "<pfad>"` holen. Anfuehrungszeichen sind ueblich,
    # aber nicht garantiert, deshalb beide Schreibweisen.
    $arg = ($task.Actions | ForEach-Object { $_.Arguments }) -join ' '
    $pfad = $null
    if ($arg -match '-File\s+"([^"]+)"')      { $pfad = $Matches[1] }
    elseif ($arg -match '-File\s+(\S+\.ps1)') { $pfad = $Matches[1] }

    # Ueber den aufgeloesten Pfad vergleichen: C:\a\..\b und C:\b sind
    # dieselbe Datei, und Windows unterscheidet keine Gross- und
    # Kleinschreibung.
    $normal = {
        param($p)
        if (-not $p) { return $null }
        try { (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path.TrimEnd('\').ToLowerInvariant() }
        catch { $p.TrimEnd('\').ToLowerInvariant() }
    }
    # Ohne deutbaren Pfad wird NICHT gewarnt: Eine fremde Bauart der Aufgabe
    # ist kein Beleg dafuer, dass sie woanders hinzeigt.
    $zeigt = if ($pfad) { (& $normal $PSCommandPath) -eq (& $normal $pfad) } else { $true }

    # DIE UHRZEIT WIRD ABGELESEN, NICHT UMGERECHNET (22.09.2026).
    #
    # StartBoundary sieht so aus: `2026-03-07T04:00:00+02:00` — mit dem
    # Zeitzonen-Versatz, der GALT, ALS die Aufgabe eingerichtet wurde. Ein
    # `[datetime]`-Wurf rechnet das auf die heutige Ortszeit um und machte
    # aus 04:00 eine 03:00, weil der 7. Maerz in der Winterzeit lag. Die
    # Aufgabenplanung startet aber nach der WANDUHR: Sie laeuft um 04:00,
    # Sommerzeit hin oder her (der naechste Lauf in derselben Abfrage sagte
    # dasselbe). Also den geschriebenen Zeitanteil nehmen, nicht den
    # umgerechneten.
    $zeit = $null
    $taeglich = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskDailyTrigger' } | Select-Object -First 1
    if ($taeglich -and $taeglich.StartBoundary) {
        try { $zeit = ([datetimeoffset]$taeglich.StartBoundary).DateTime.ToString('HH:mm') } catch { }
    }

    $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    $wann = { param($d) if ($d -and $d.Year -gt 2000) { $d.ToString('dd.MM.yyyy HH:mm') } else { $null } }

    return [pscustomobject]@{
        eingerichtet  = $true
        zeit          = $zeit
        pfad          = $pfad
        zeigtHierher  = $zeigt
        naechsterLauf = & $wann $info.NextRunTime
        letzterLauf   = & $wann $info.LastRunTime
        aufgabe       = $taskName
        hier          = $PSCommandPath
        # 7 ist die Vorgabe der Aufgabenplanung (niedrig), 4 traegt
        # Register-UpdateTask ein. Das Fenster zeigt den Unterschied an.
        prioritaet    = $(try { [int]$task.Settings.Priority } catch { $null })
    }
}

function Test-PrioritaetNiedrig {
    <# 7 bis 10 sind in der Aufgabenplanung "unter normal" bis "Leerlauf". #>
    param($Prioritaet)
    return ($null -ne $Prioritaet -and [int]$Prioritaet -ge 7)
}

function Test-AufgabeZeigtHierher {
    <#
        Zeigt die eingetragene Aufgabenplanung auf DIESE Datei?

        WOFUER (22.09.2026, gemessen und nicht vermutet)
        Der Manager liegt seit dem 21.09.2026 im Monorepo, und die alte Kopie
        auf dem Desktop sollte damit erledigt sein. War sie nicht: Die
        Aufgabe "UpdateManager-SilentMode" startete weiter
        `C:\Users\<name>\Desktop\update_manager\universal-update-manager.ps1`.
        Im Protokoll stand das schwarz auf weiss, zwei Zeilen untereinander —
        der Lauf von Hand lud die Konfiguration aus dem Repo, der naechtliche
        aus dem Desktop-Ordner. 466 Zeilen Unterschied lagen dazwischen, und
        der naechtliche Lauf war der aeltere: ohne Auftragsmodus, ohne
        Nachlauf fuer Benutzer-Pakete, ohne UTF-8-Protokoll.

        Gemerkt hat das niemand, weil beide Fassungen sauber durchliefen.
        Genau diese Sorte Abweichung faellt nur auf, wenn jemand danach
        SUCHT — also fragt der Manager es sich jetzt bei jedem Start selbst.
        Er aendert dabei nichts: Eine Aufgabe umzuhaengen ist eine
        Entscheidung, keine Nebenwirkung eines Updatelaufs.
    #>
    $a = Get-AufgabeInfo
    # Bei der Gelegenheit: Laeuft die Aufgabe noch mit der niedrigen
    # Vorgabe-Prioritaet, steht das im Protokoll, bis sie neu eingerichtet
    # ist. Geaendert wird auch hier nichts von selbst.
    if ($a.eingerichtet -and (Test-PrioritaetNiedrig $a.prioritaet)) {
        Write-Log "$($T['task_prio_niedrig']) ($($a.prioritaet))" "WARNING"
    }
    if (-not $a.eingerichtet -or $a.zeigtHierher -or -not $a.pfad) { return $true }
    $dort = $a.pfad

    Write-Log "$($T['task_fremde_datei']) [$($T['task_fremde_hier']): $PSCommandPath] [$($T['task_fremde_dort']): $dort]" "WARNING"
    if (-not $SilentMode) {
        Write-Host ""
        Write-Host $T['task_fremde_datei'] -ForegroundColor $ColorWarning
        Write-Host "  $($T['task_fremde_hier']): $PSCommandPath" -ForegroundColor White
        Write-Host "  $($T['task_fremde_dort']): $dort" -ForegroundColor White
        Write-Host "  $($T['task_fremde_hilfe'])" -ForegroundColor $ColorInfo
        Write-Host ""
    }
    return $false
}

function Register-UpdateTask {
    param([string]$TimeInput)

    $parts  = $TimeInput -split ":"
    $hour   = [int]$parts[0]
    $minute = [int]$parts[1]
    $taskName   = $AufgabeName
    $scriptPath = $PSCommandPath
    $psExe      = "powershell.exe"
    $pwshPath   = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $pwshPath) { $psExe = $pwshPath }
    $triggerTime = (Get-Date).Date.AddHours($hour).AddMinutes($minute)

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host $T['task_replacing'] -ForegroundColor $ColorWarning
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    # Trigger 1: Taeglich zur konfigurierten Zeit
    $triggerDaily = New-ScheduledTaskTrigger -Daily -At $triggerTime
    # Trigger 2: Bei Login als Fallback (2 Min Verzoegerung damit Windows fertig bootet)
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $triggerLogon.Delay = "PT2M"

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -SilentMode"
    # PRIORITAET 4 STATT DER VORGABE 7 (03.10.2026).
    #
    # Ohne Angabe traegt die Aufgabenplanung 7 ein. Das ist nicht nur
    # "etwas weniger Rechenzeit": Der Prozess und alles, was er startet
    # (winget, choco, die Jobs), laeuft dann mit niedriger Platten- und
    # Speicherprioritaet. Auf einem Rechner, der nachts noch anderes tut,
    # kommt er als Letzter dran — und die Zeitgrenzen laufen nach der
    # Wanduhr weiter. 4 ist die normale Prioritaet eines Programms, das
    # jemand von Hand startet; mehr braucht es nicht.
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -Priority 4
    # Als aktueller Benutzer ausfuehren damit Winget (per-user installiert) erreichbar ist
    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Trigger @($triggerDaily, $triggerLogon) -Action $action -Settings $settings -Principal $principal `
        -Description "Universal Update Manager - Silent Mode (Winget + Chocolatey)" -Force | Out-Null

    Write-Host "`n$($T['task_done'])" -ForegroundColor $ColorSuccess
    Write-Host "$($T['task_label_name']): $taskName" -ForegroundColor White
    Write-Host "$($T['task_label_time']): $TimeInput $($T['task_daily'])" -ForegroundColor White
    Write-Host "$($T['task_label_mode']): $($T['task_mode_desc'])" -ForegroundColor White
    Write-Host "$($T['task_label_missed']): $($T['task_missed_desc'])`n" -ForegroundColor White
    Write-Log "Task Scheduler configured: $taskName at $TimeInput" "SUCCESS"
}

function Set-ScheduledUpdateTask {
    Clear-Host
    Show-SectionHeader $T['task_title']

    $taskName = $AufgabeName
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    # Aktuellen Task anzeigen falls vorhanden
    if ($existing) {
        $info    = $existing | Get-ScheduledTaskInfo
        $trigger = $existing.Triggers | Select-Object -First 1
        $nextRun = if ($info.NextRunTime -and $info.NextRunTime.Year -gt 2000) { $info.NextRunTime.ToString("dd.MM.yyyy HH:mm") } else { "-" }
        $lastRun = if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime.ToString("dd.MM.yyyy HH:mm") } else { $T['task_last_run_none'] }
        $timeStr = if ($trigger.StartBoundary) { ([datetime]$trigger.StartBoundary).ToString("HH:mm") } else { "-" }

        Write-Host "--------------------------------------------" -ForegroundColor $ColorHeader
        Write-Host "$($T['task_current']):" -ForegroundColor $ColorInfo
        Write-Host "  $($T['task_label_time']): $timeStr $($T['task_daily'])" -ForegroundColor White
        Write-Host "  $($T['task_status']):  $($existing.State)" -ForegroundColor White
        Write-Host "  $($T['task_next_run']): $nextRun" -ForegroundColor White
        Write-Host "  $($T['task_last_run']): $lastRun" -ForegroundColor White
        Write-Host "--------------------------------------------`n" -ForegroundColor $ColorHeader

        Write-Host "$($T['task_action_prompt'])" -ForegroundColor $ColorInfo
        Write-Host "  $($T['task_action_update'])" -ForegroundColor White
        if ($UILang -eq "de") {
            Write-Host "  L - Task löschen" -ForegroundColor White
        } else {
            Write-Host "  D - Delete task" -ForegroundColor White
        }
        Write-Host "  Enter - $($T['task_action_back'])`n" -ForegroundColor $ColorWarning

        $action = Read-SingleKey $T['menu_prompt']

        if ($action -eq "U" -or $action -eq "u") {
            # Uhrzeit ändern — weiter unten
        } elseif ($action -eq "L" -or $action -eq "l" -or $action -eq "D" -or $action -eq "d") {
            Write-Host ""
            $confirm = Read-SingleKey "$($T['task_delete_confirm']) $($T['yes_no_prompt'])"
            if (Test-YesResponse $confirm) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "`n$($T['task_deleted'])`n" -ForegroundColor $ColorSuccess
                Write-Log "Task deleted: $taskName" "SUCCESS"
            }
            Wait-AnyKey
            return
        } else {
            return
        }
    } else {
        Write-Host "$($T['task_no_task'])`n" -ForegroundColor $ColorWarning
    }

    # Uhrzeit eingeben
    Write-Host $T['task_prompt_time'] -ForegroundColor $ColorInfo
    Write-Host "$($T['task_prompt_hint'])`n" -ForegroundColor $ColorInfo
    $timeInput = Read-Host $T['task_prompt_input']

    if ($timeInput -notmatch "^\d{1,2}:\d{2}$") {
        Write-Host "`n$($T['task_invalid_format'])`n" -ForegroundColor $ColorError
        Wait-AnyKey
        return
    }

    $parts  = $timeInput -split ":"
    $hour   = [int]$parts[0]
    $minute = [int]$parts[1]

    if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59) {
        Write-Host "`n$($T['task_invalid_time'])`n" -ForegroundColor $ColorError
        Wait-AnyKey
        return
    }

    try {
        Register-UpdateTask -TimeInput $timeInput
    } catch {
        Write-Host "`n$($T['task_error']): $($_.Exception.Message)`n" -ForegroundColor $ColorError
        Write-Log "$($T['task_error']): $($_.Exception.Message)" "ERROR"
    }

    Wait-AnyKey
}

# ============================================
# MENÜ / MENU
# ============================================

function Show-Menu {
    Clear-Host
    Write-Host "`n"
    Write-Host "============================================" -ForegroundColor $ColorHeader
    Write-Host $T['menu_title'] -ForegroundColor $ColorHeader
    Write-Host "============================================`n" -ForegroundColor $ColorHeader
    Write-Host $T['menu_1']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_2']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_3']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_4']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_5']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_6']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_7']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_8']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_9']  -ForegroundColor $ColorInfo
    Write-Host $T['menu_10'] -ForegroundColor $ColorInfo
    Write-Host $T['menu_0']  -ForegroundColor $ColorWarning
    Write-Host ""
}

# ============================================
# SYSTEM-INFO
# ============================================

function Show-OffeneUpdates {
    # Nachsehen, ohne etwas anzufassen. Es gab bisher keinen Weg, das zu
    # fragen: Jeder Menuepunkt fing sofort an zu installieren. Wer ein
    # fremdes Geraet in der Hand hat, will aber erst sehen, was ansteht.
    Show-SectionHeader $T['check_title']

    if (Test-WingetAvailable) {
        Write-Host "$($T['check_winget'])" -ForegroundColor $ColorInfo
        # --include-unknown: Pakete ohne erkennbare Version fallen sonst raus
        # und fehlen genau dort, wo man sie am ehesten sucht.
        $roh = winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String
        $zeilen = ($roh -split "`r?`n") | Where-Object { $_ -match '\S' }
        $treffer = $zeilen | Where-Object { $_ -match '\s(winget|msstore)\s*$' }
        if ($treffer) {
            $treffer | ForEach-Object { Write-Host "   $($_.Trim())" -ForegroundColor White }
            Write-Host "   $($treffer.Count) $($T['check_found'])`n" -ForegroundColor $ColorWarning
            Write-Log "$($T['check_winget']) $($treffer.Count)" "INFO"
        } else {
            Write-Host "   $($T['check_none'])`n" -ForegroundColor $ColorSuccess
        }
    } else {
        Write-Host "   $($T['winget_not_installed'])`n" -ForegroundColor $ColorWarning
    }

    if (Test-ChocoAvailable) {
        Write-Host "$($T['check_choco'])" -ForegroundColor $ColorInfo
        $rohC = choco outdated -r 2>&1 | Out-String
        $zeilenC = ($rohC -split "`r?`n") | Where-Object { $_ -match '\|' }
        if ($zeilenC) {
            $zeilenC | ForEach-Object {
                $teile = $_ -split '\|'
                Write-Host "   $($teile[0])  $($teile[1]) -> $($teile[2])" -ForegroundColor White
            }
            Write-Host "   $($zeilenC.Count) $($T['check_found'])`n" -ForegroundColor $ColorWarning
            Write-Log "$($T['check_choco']) $($zeilenC.Count)" "INFO"
        } else {
            Write-Host "   $($T['check_none'])`n" -ForegroundColor $ColorSuccess
        }
    }

    # Windows Update gehoert zum Nachsehen dazu (03.10.2026). Bis dahin sah
    # "Nachsehen" nur bei winget und Chocolatey nach — ein wartendes
    # Windows-Update kam im Fenster schlicht nicht vor, und "Alles aktuell"
    # stand trotzdem da. Gesucht wird direkt beim Dienst, ohne das Modul.
    if (-not ($Global:Config -and -not $Global:Config.updateSources.windowsUpdate.enabled)) {
        Write-Host "$($T['check_windows'])" -ForegroundColor $ColorInfo
        $wuGrenze = if ($Global:Config -and $Global:Config.updateSources.windowsUpdate.timeoutSeconds) { $Global:Config.updateSources.windowsUpdate.timeoutSeconds } else { 120 }
        $wuTitel = Lies-JobAusgabe (Search-WindowsUpdateTitel -TimeoutSeconds $wuGrenze) $T['wu_timeout'] $wuGrenze
        if ($null -ne $wuTitel) {
            if ($wuTitel.Count -gt 0) {
                $wuTitel | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
                Write-Host "   $($wuTitel.Count) $($T['check_found'])`n" -ForegroundColor $ColorWarning
                Write-Log "$($T['check_windows']) $($wuTitel.Count)" "INFO"
            } else {
                Write-Host "   $($T['check_none'])`n" -ForegroundColor $ColorSuccess
            }
            Write-WindowsWeitereUpdates -Bekannt @($wuTitel | ForEach-Object { "$_" }) -TimeoutSeconds $wuGrenze
        }
    }
}

function Show-SystemInfo {
    Clear-Host
    Show-SectionHeader $T['sysinfo_title']

    $hw = Get-HardwareInfo

    Write-Host $T['sysinfo_hardware'] -ForegroundColor $ColorInfo
    Write-Host "$($T['sysinfo_cpu']): $($hw.CPU)" -ForegroundColor White
    Write-Host "$($T['sysinfo_gpu']): $($hw.GPU)" -ForegroundColor White
    Write-Host "$($T['sysinfo_board']): $($hw.Mainboard)`n" -ForegroundColor White

    Write-Host $T['sysinfo_sources'] -ForegroundColor $ColorInfo
    Write-Host "$($T['sysinfo_winget']): $(if (Test-WingetAvailable) { $T['available'] } else { $T['not_found'] })" -ForegroundColor $(if (Test-WingetAvailable) { $ColorSuccess } else { $ColorError })
    Write-Host "$($T['sysinfo_choco']): $(if (Test-ChocoAvailable) { $T['available'] } else { $T['not_found'] })" -ForegroundColor $(if (Test-ChocoAvailable) { $ColorSuccess } else { $ColorError })
    Write-Host "$($T['sysinfo_pswu']): $(if (Test-PSWindowsUpdateModule) { $T['available'] } else { $T['not_found'] })" -ForegroundColor $(if (Test-PSWindowsUpdateModule) { $ColorSuccess } else { $ColorError })
    Write-Host "$($T['sysinfo_internet']): $(if (Test-InternetConnection) { $T['connected'] } else { $T['offline'] })`n" -ForegroundColor $(if (Test-InternetConnection) { $ColorSuccess } else { $ColorError })

    Write-Host $T['sysinfo_config'] -ForegroundColor $ColorInfo
    if ($Global:Config) {
        Write-Host "$($T['sysinfo_config_file']): $($T['loaded'])" -ForegroundColor $ColorSuccess
        Write-Host "$($T['sysinfo_winget_cfg']): $(if ($Global:Config.updateSources.winget.enabled) { $T['enabled'] } else { $T['disabled'] })" -ForegroundColor White
        Write-Host "$($T['sysinfo_choco_cfg']): $(if ($Global:Config.updateSources.chocolatey.enabled) { $T['enabled'] } else { $T['disabled'] })" -ForegroundColor White
        Write-Host "$($T['sysinfo_wu_cfg']): $(if ($Global:Config.updateSources.windowsUpdate.enabled) { $T['enabled'] } else { $T['disabled'] })" -ForegroundColor White
        Write-Host "$($T['sysinfo_store_cfg']): $(if ($Global:Config.updateSources.microsoftStore.enabled) { $T['enabled'] } else { $T['disabled'] })`n" -ForegroundColor White
    } else {
        Write-Host "$($T['sysinfo_config_file']): $($T['not_loaded'])`n" -ForegroundColor $ColorWarning
    }

    Write-Host ""; Wait-AnyKey
}

# ============================================
# HAUPTPROGRAMM / MAIN
# ============================================

function Main {
    Write-Log "========================================" "INFO"
    Write-Log $T['log_started'] "INFO"
    Write-Log "========================================" "INFO"

    $Global:Config = Get-UpdateConfig
    Test-Prerequisites | Out-Null
    Test-AufgabeZeigtHierher | Out-Null
    $hardware = Get-HardwareInfo

    do {
        Show-Menu
        $choice = Read-SingleKey $T['menu_prompt']

        switch ($choice) {
            "1" {
                $startTime = Get-Date
                Write-Log $T['log_full_start'] "INFO"
                Update-Winget
                Update-Chocolatey
                Update-Windows
                Update-MicrosoftStore
                Update-NVIDIA -Hardware $hardware
                Update-AMD    -Hardware $hardware
                Update-Intel  -Hardware $hardware
                Update-MSI    -Hardware $hardware
                $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

                Write-Host "`n============================================" -ForegroundColor $ColorHeader
                Write-Host $T['summary_title'] -ForegroundColor $ColorHeader
                Write-Host "============================================" -ForegroundColor $ColorHeader
                Write-Host "$($T['summary_duration']): $duration $($T['summary_minutes'])" -ForegroundColor White
                Write-Host $T['summary_checked'] -ForegroundColor White
                if ($hardware.HasNVIDIA) { Write-Host $T['summary_nvidia'] -ForegroundColor $ColorSuccess }
                if ($hardware.HasAMD)    { Write-Host $T['summary_amd']    -ForegroundColor $ColorSuccess }
                if ($hardware.HasIntel)  { Write-Host $T['summary_intel']  -ForegroundColor $ColorSuccess }
                if ($hardware.HasMSI)    { Write-Host $T['summary_msi']    -ForegroundColor $ColorSuccess }
                Write-Host "$($T['summary_log']): $LogFile" -ForegroundColor $ColorInfo
                Write-Host "============================================`n" -ForegroundColor $ColorHeader
                Write-Log $T['summary_done'] "SUCCESS"
                Wait-AnyKey
            }
            "2"  { Update-Winget;        Write-Host ""; Wait-AnyKey }
            "3"  { Update-Chocolatey;    Write-Host ""; Wait-AnyKey }
            "4"  { Update-Windows;       Write-Host ""; Wait-AnyKey }
            "5"  { Update-MicrosoftStore; Write-Host ""; Wait-AnyKey }
            "6"  {
                Update-NVIDIA -Hardware $hardware
                Update-AMD    -Hardware $hardware
                Update-Intel  -Hardware $hardware
                Update-MSI    -Hardware $hardware
                Write-Host ""; Wait-AnyKey
            }
            "7"  {
                Invoke-SilentUpdate
                Write-Host "`n$($T['silent_result']): $LogFile`n" -ForegroundColor $ColorSuccess
                Wait-AnyKey
            }
            "8"  { Set-ScheduledUpdateTask }
            "9"  { Show-SystemInfo }
            { $_ -eq "L" -or $_ -eq "l" } {
                if (-not (Show-Protokoll)) { Write-Host ""; Wait-AnyKey }
            }
            "0"  {
                Write-Log $T['log_stopped'] "INFO"
                Write-Host "`n$($T['goodbye'])`n" -ForegroundColor $ColorSuccess
                exit
            }
            default {
                Write-Host "`n$($T['invalid_choice'])`n" -ForegroundColor $ColorError
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

# ============================================
# START
# ============================================

function Split-Auftrag {
    <#
        Zerlegt den Wert von `-Auftrag` in einzelne Namen.

        AUCH AN LEERRAUM (03.10.2026). Das Fenster haengte die Namen mit
        Komma und OHNE Anfuehrungszeichen an `-Command`. PowerShell liest
        `winget,choco` dort als Liste, und eine Liste, die an `[string]`
        gebunden wird, kommt mit LEERZEICHEN verbunden an: "winget choco".
        Getrennt wurde nur an Komma und Semikolon, also blieb ein einziger
        Name uebrig, den es nicht gibt — mehr als ein Schalter im Fenster
        hiess "Unbekannter Auftrag". Das Fenster setzt die Namen jetzt in
        Anfuehrungszeichen; hier wird trotzdem an allem getrennt, was als
        Trenner ankommen kann, damit derselbe Fehler nicht ueber einen
        anderen Aufrufer zurueckkommt.
    #>
    param([string]$Auftrag)
    return ,@($Auftrag -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Einen einzelnen Auftrag ausfuehren und zurueckkehren. Ruft genau die
# Funktionen, die auch das Menue ruft - kein zweiter Weg durch dieselbe Arbeit.
function Invoke-Auftrag {
    param([string[]]$Namen)

    # Keine Rueckfragen: Dieser Lauf hat keine Tastatur (siehe Read-SingleKey).
    $Global:OhneRueckfrage = $true

    $Global:Config = Get-UpdateConfig
    # Die Zustimmung ist der Knopf in der Oberflaeche gewesen. Ohne das
    # stuende hier die Frage "Updates installieren?" an eine Konsole, die es
    # nicht gibt. Nur fuer DIESEN Lauf, die Datei bleibt unberuehrt.
    if (($Namen -notcontains 'pruefen') -and $Global:Config) {
        try {
            $Global:Config.updateSources.winget.autoAccept = $true
            $Global:Config.updateSources.chocolatey.autoAccept = $true
        } catch { }
    }
    Test-Prerequisites | Out-Null
    Test-AufgabeZeigtHierher | Out-Null
    $hardware = Get-HardwareInfo

    foreach ($Name in $Namen) {
        switch ($Name) {
            'winget'  { Update-Winget }
            'choco'   { Update-Chocolatey }
            'windows' { Update-Windows }
            'store'   { Update-MicrosoftStore }
            'treiber' {
                Update-NVIDIA -Hardware $hardware
                Update-AMD    -Hardware $hardware
                Update-Intel  -Hardware $hardware
                Update-MSI    -Hardware $hardware
            }
            'pruefen' { Show-OffeneUpdates }
            'alles'   {
                Update-Winget
                Update-Chocolatey
                Update-Windows
                Update-MicrosoftStore
                Update-NVIDIA -Hardware $hardware
                Update-AMD    -Hardware $hardware
                Update-Intel  -Hardware $hardware
                Update-MSI    -Hardware $hardware
            }
        }
    }
}

function Get-ProtokollNeuestZuerst {
    <#
        Ordnet die Zeilen des Protokolls so, dass der neueste LAUF oben steht.

        Ein Lauf beginnt mit dem Dreiklang "====", Titelzeile, "====" (so
        schreiben ihn der stille Lauf und das Menue). Die Laeufe werden in
        umgekehrter Reihenfolge ausgegeben, INNERHALB eines Laufs bleibt es
        chronologisch: Wer einen Lauf liest, liest ihn von oben nach unten.
        Zeilen vor dem ersten Lauf (z. B. Meldungen der Oberflaeche) bilden
        einen eigenen Block und stehen dann ganz unten.

        Der Schluss eines stillen Laufs ist ebenfalls "====", EINE Zeile,
        "====" (die Zeile mit [SILENT-DONE]); sie darf nicht als Anfang gelten.
        Bekannte Grenze: Ein Lauf mit genau EINER Zeile zwischen Kopf und
        Schluss wuerde als zwei Laeufe gelesen; echte Laeufe haben immer mehr
        (Anlauf, Konfiguration), und es ginge nichts verloren, nur die Gruppierung.

        Rein, ohne Dateizugriff: die Probe kann sie mit Text fuettern.
    #>
    param([string[]]$Zeilen)

    $trenner = '^\[[^\]]*\] \[[A-Z-]+\] ={10,}\s*$'
    $bloecke = New-Object System.Collections.Generic.List[object]
    $aktuell = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Zeilen.Count; $i++) {
        $z = $Zeilen[$i]
        $istStart = $z -match $trenner -and
                    ($i + 2) -lt $Zeilen.Count -and
                    $Zeilen[$i + 1] -notmatch $trenner -and
                    $Zeilen[$i + 1] -notmatch '\[SILENT-(DONE|FAILED)\]' -and
                    $Zeilen[$i + 2] -match $trenner
        if ($istStart -and $aktuell.Count -gt 0) {
            $bloecke.Add($aktuell.ToArray())
            $aktuell = New-Object System.Collections.Generic.List[string]
        }
        $aktuell.Add($z)
    }
    if ($aktuell.Count -gt 0) { $bloecke.Add($aktuell.ToArray()) }

    $aus = New-Object System.Collections.Generic.List[string]
    for ($k = $bloecke.Count - 1; $k -ge 0; $k--) {
        foreach ($z in $bloecke[$k]) { $aus.Add($z) }
    }
    return $aus.ToArray()
}

function Show-Protokoll {
    # Schreibt die Ansicht in eine Wegwerfdatei und oeffnet SIE, nicht das
    # Protokoll. UTF-8 mit BOM, damit der Editor die Umlaute sicher erkennt.
    if (-not (Test-Path -LiteralPath $LogFile)) {
        Write-Host "$($T['log_not_found'])" -ForegroundColor $ColorError
        return $false
    }
    $zeilen = [System.IO.File]::ReadAllLines($LogFile, [System.Text.Encoding]::UTF8)
    $ordnung = Get-ProtokollNeuestZuerst -Zeilen $zeilen
    $ziel = Join-Path ([System.IO.Path]::GetTempPath()) ("UpdateManager-Protokoll-{0}.txt" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    # Reste frueherer Ansichten (aelter als ein Tag) wegraeumen.
    Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter 'UpdateManager-Protokoll-*.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $inhalt = @("# $($T['log_ansicht_hinweis'])", '') + $ordnung
    [System.IO.File]::WriteAllLines($ziel, $inhalt, (New-Object System.Text.UTF8Encoding $true))
    Start-Process notepad.exe -ArgumentList "`"$ziel`""
    return $true
}

function Invoke-LogPflege {
    <#
        Haelt das Protokoll 7 Tage (03.10.2026, Davids Wunsch).

        Vorher gab es ZWEI Rotationen nach Groesse, die nichts voneinander
        wussten: ganz oben im Skript ab 5 MB in datierte Archive, hier ab
        1 MB nach `.1`. Die obere griff nie, weil die untere frueher zog;
        und keine von beiden beantwortete die Frage, die man an ein Protokoll
        wirklich hat — wie weit reicht es zurueck. Die Antwort ist jetzt
        eine Zahl: sieben Tage, bei jedem Start nachgezogen.

        Kleiner Nebeneffekt, der gewollt ist: Zwei Stellen lesen die Datei
        bei jedem Start ganz (die Kodierungs-Reparatur und die Pruefung, ob
        der stille Lauf heute schon war). Mit sieben Tagen bleibt das kurz.

        `-Jetzt` gibt es fuer die Probe: Ein Test, der vom Tag abhaengt, an
        dem er laeuft, ist keiner.
    #>
    param([string]$Pfad, [int]$Tage = 7, [datetime]$Jetzt = (Get-Date))

    # Der Zeitstempel am Zeilenanfang sortiert sich als Text richtig
    # (yyyy-MM-dd HH:mm:ss); verglichen wird deshalb ohne Umrechnen.
    $grenze     = $Jetzt.AddDays(-$Tage)
    $grenzeText = $grenze.ToString('yyyy-MM-dd HH:mm:ss')

    try {
        if (Test-Path -LiteralPath $Pfad) {
            $zeilen   = [System.IO.File]::ReadAllLines($Pfad, [System.Text.Encoding]::UTF8)
            $behalten = New-Object System.Collections.Generic.List[string]
            $vorspann = New-Object System.Collections.Generic.List[string]
            $halten   = $null       # unbekannt, bis der erste Zeitstempel kommt
            $entfernt = 0
            foreach ($z in $zeilen) {
                if ($z.Length -ge 21 -and $z -match '^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]') {
                    $halten = ([string]::CompareOrdinal($Matches[1], $grenzeText) -ge 0)
                }
                # Zeilen ohne Zeitstempel (mehrzeilige Meldungen) teilen das
                # Schicksal der Zeile, zu der sie gehoeren.
                if ($null -eq $halten) { $vorspann.Add($z) }
                elseif ($halten)       { $behalten.Add($z) }
                else                   { $entfernt++ }
            }
            # NUR SCHREIBEN, WENN ETWAS WEGFAELLT. An sechs von sieben Tagen
            # ist nichts zu tun; die Datei dann trotzdem neu zu schreiben,
            # waere bei jedem Start ein Fenster, in dem ein zweiter Lauf
            # seine Zeile verliert.
            if ($entfernt -gt 0) {
                $neu = "$Pfad.neu"
                # Die Zwischendatei wird NEU angelegt, nie ueberschrieben
                # (Fund des Pruefers, 03.10.2026). Der Protokollordner liegt
                # in ProgramData, dort duerfen auch unerhoehte Prozesse
                # Dateien anlegen: Laege unter diesem Namen schon ein Link,
                # schriebe der erhoehte Lauf in dessen Ziel. Ein Rest aus
                # einem abgebrochenen Lauf wird entfernt, wenn er eine
                # gewoehnliche Datei ist; alles andere bricht die Pflege ab
                # (und steht dann als Warnung im Protokoll).
                if (Test-Path -LiteralPath $neu) {
                    $rest = Get-Item -LiteralPath $neu -Force
                    if ($rest.PSIsContainer -or ($rest.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        throw "$neu $($T['log_neu_belegt'])"
                    }
                    Remove-Item -LiteralPath $neu -Force -ErrorAction Stop
                }
                $strom = New-Object System.IO.FileStream($neu, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
                try {
                    $schreiber = New-Object System.IO.StreamWriter($strom, (New-Object System.Text.UTF8Encoding $true))
                    foreach ($z in $behalten) { $schreiber.WriteLine($z) }
                    $schreiber.Flush()
                } finally { $strom.Dispose() }
                Move-Item -LiteralPath $neu -Destination $Pfad -Force -ErrorAction Stop
                Write-Log "$($T['log_gekuerzt']): $($entfernt + $vorspann.Count) ($Tage $($T['log_tage']))" "INFO"
            }
        }

        # Altdateien daneben: die Sicherung vom Umkodieren (21.09.2026), die
        # `.1` der frueheren Rotation ab 1 MB und die datierten Archive der
        # noch frueheren ab 5 MB. Dieselbe Frist wie fuer die Zeilen. Jede
        # Datei einzeln beim Namen, kein Platzhalter ueber den Ordner hinaus.
        $ordner = Split-Path -Parent $Pfad
        $stamm  = [System.IO.Path]::GetFileNameWithoutExtension($Pfad)
        $alt = @("$Pfad.ansi-sicherung", "$Pfad.1")
        if ($ordner -and (Test-Path -LiteralPath $ordner)) {
            $alt += @(Get-ChildItem -LiteralPath $ordner -Filter "${stamm}_*.log" -File -ErrorAction SilentlyContinue |
                      ForEach-Object { $_.FullName })
        }
        foreach ($datei in $alt) {
            if (-not (Test-Path -LiteralPath $datei)) { continue }
            if ((Get-Item -LiteralPath $datei).LastWriteTime -ge $grenze) { continue }
            Remove-Item -LiteralPath $datei -Force -ErrorAction Stop
            Write-Log "$($T['log_altdatei']): $(Split-Path -Leaf $datei)" "INFO"
        }
    } catch {
        # Ein Protokoll, das sich nicht kuerzen laesst, haelt keinen
        # Updatelauf auf — aber es wird gesagt, sonst waechst es still.
        Write-Log "$($T['log_pflege_fehler']): $($_.Exception.Message)" "WARNING"
    }
}

try {
    # ZUERST, ohne Protokoll und ohne Vorbereitung: Diese Ausgabe liest ein
    # anderes Programm, und zwischen Anfrage und Antwort gehoert nichts als
    # die Antwort. Sie aendert nichts und braucht keine Rechte.
    if ($AufgabeStatus) {
        Get-AufgabeInfo | ConvertTo-Json -Compress
        exit 0
    }

    # Nur lesen und anzeigen, ohne Rechte und ohne Pflege der Datei.
    if ($ProtokollAnzeigen) {
        if (Show-Protokoll) { exit 0 } else { exit 1 }
    }

    # Alles ausser der reinen Abfrage oben aendert etwas am System und
    # braucht deshalb Rechte. Frueher stand dafuer `#Requires` im Kopf; das
    # galt der ganzen Datei und sperrte auch das Nachsehen aus.
    if (-not (Test-Erhoeht)) {
        Write-Host $T['braucht_rechte'] -ForegroundColor $ColorError
        Write-Host $T['braucht_rechte_wie'] -ForegroundColor $ColorInfo
        exit 4
    }

    Repair-LogKodierung -Pfad $LogFile
    Invoke-LogPflege -Pfad $LogFile

    if ($AufgabeZeit) {
        if ($AufgabeZeit -notmatch '^([01]?\d|2[0-3]):([0-5]\d)$') {
            Write-Host $T['task_invalid_format'] -ForegroundColor $ColorError
            exit 2
        }
        if (-not (Test-Erhoeht)) {
            # Eine Aufgabe mit hoechsten Rechten laesst sich nur erhoeht
            # eintragen. Das GESAGT statt an einem "Zugriff verweigert"
            # scheitern zu lassen, das niemand einordnen kann.
            Write-Host $T['task_braucht_rechte'] -ForegroundColor $ColorError
            exit 3
        }
        Register-UpdateTask -TimeInput $AufgabeZeit
        exit 0
    }

    if ($Auftrag) {
        $ERLAUBT = @('alles', 'winget', 'choco', 'windows', 'store', 'treiber', 'pruefen')
        $namen = Split-Auftrag $Auftrag
        $unbekannt = @($namen | Where-Object { $ERLAUBT -notcontains $_ })
        if ($unbekannt.Count -gt 0) {
            # Auch ins Protokoll (03.10.2026): Die Zeile stand bisher nur auf
            # der Konsole. Ein Fenster, das schon zu ist, hinterliess damit
            # keine Spur davon, dass der Lauf gar nicht erst begonnen hat.
            # Der Wert kommt von aussen: ohne Steuerzeichen und gekuerzt ins
            # Protokoll, damit er dort keine eigenen Zeilen aufmachen kann.
            $gezeigt = ($Auftrag -replace '[\x00-\x1F\x7F]', ' ')
            if ($gezeigt.Length -gt 80) { $gezeigt = $gezeigt.Substring(0, 80) + '…' }
            Write-Log "Unbekannter Auftrag, uebergeben: '$gezeigt'" "ERROR"
            Write-Host ("Moeglich sind: " + ($ERLAUBT -join ', ')) -ForegroundColor $ColorInfo
            exit 2
        }
        Invoke-Auftrag -Namen $namen
        exit (Get-LaufExitCode)
    }

    if ($SilentMode) {
        $Global:Config = Get-UpdateConfig

        # Lock-File: verhindert doppelte Silent-Mode-Laeufe (z.B. durch Daily + AtLogOn Trigger)
        $lockFile = Join-Path $env:TEMP "UpdateManager-SilentMode.lock"
        if (Test-Path $lockFile) {
            $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
            if ($lockAge.TotalMinutes -lt 15) {
                Write-Log "Silent Mode laeuft bereits (Lock: $([math]::Round($lockAge.TotalMinutes, 1)) min alt)" "WARNING"
                exit 0
            }
        }
        New-Item -Path $lockFile -ItemType File -Force | Out-Null

        try {
            # Internet-Retry: nach dem Hochfahren ist Netzwerk evtl. noch nicht bereit
            $internetOk = $false
            for ($retry = 1; $retry -le 5; $retry++) {
                if (Test-InternetConnection) {
                    $internetOk = $true
                    break
                }
                Write-Log "Kein Internet, Versuch $retry/5 - warte 30s..." "WARNING"
                Start-Sleep -Seconds 30
            }
            if (-not $internetOk) {
                Write-Log $T['no_internet'] "ERROR"
                exit 0
            }
            Write-Log $T['internet_ok'] "SUCCESS"
            Invoke-SilentUpdate
        } finally {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        Main
    }
} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    if (-not $SilentMode) {
        Write-Host "`nCRITICAL ERROR: $($_.Exception.Message)`n" -ForegroundColor $ColorError
        Wait-AnyKey
    }
    exit 1
}
