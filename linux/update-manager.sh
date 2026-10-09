#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 MelucioLabs / David Vaupel
#
# MelucioLabs Update-Manager fuer Linux und macOS.
#
# Eine Datei, keine Abhaengigkeiten ausser bash (auch das bash 3.2 von
# macOS: deshalb keine assoziativen Arrays, kein mapfile, kein ${x,,}).
#
#   --pruefen        (Vorgabe) nachsehen, was ansteht, nichts installieren
#   --aktualisieren  installieren, vorher je Quelle eine Rueckfrage
#   -y / --ja        ohne Rueckfrage (Firmware bleibt trotzdem aussen vor)
#
# Erkannt werden: mintupdate-cli (Linux Mint), apt, dnf, pacman, zypper,
# flatpak, snap, fwupdmgr (Firmware/BIOS); auf dem Mac softwareupdate, brew,
# mas. Was fehlt, wird still uebersprungen und steht nur in der
# Zusammenfassung als "nicht vorhanden".
#
# Root nur dort, wo es gebraucht wird: Das Skript selbst laeuft als normaler
# Benutzer, einzelne Schritte (apt-get update, apt-get upgrade, ...) laufen
# ueber sudo. Wer es als root startet, braucht kein sudo.
#
# Exit-Code: 0 = alles gelaufen, 1 = mindestens eine Quelle mit Fehler,
#            2 = falscher Aufruf.

# Die pruefe_*-Funktionen werden ueber ihren Namen aufgerufen.
# shellcheck disable=SC2329
set -u

UM_VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Sprache: LC_ALL vor LC_MESSAGES vor LANG, wie es auch die C-Bibliothek tut.
# ---------------------------------------------------------------------------
SPRACHE=en
_loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
case "$_loc" in
    de|de_*|de.*|de-*) SPRACHE=de ;;
esac

# L "deutsch" "english" -> gibt den Text in der erkannten Sprache aus.
L() {
    if [ "$SPRACHE" = de ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# ---------------------------------------------------------------------------
# Aufruf
# ---------------------------------------------------------------------------
MODUS=pruefen
JA=0
FARBE=auto

hilfe() {
    if [ "$SPRACHE" = de ]; then
        cat <<'EOF'
MelucioLabs Update-Manager für Linux und macOS

Aufruf:
  update-manager.sh [--pruefen | --aktualisieren] [-y] [--keine-farbe]

  --pruefen         Nachsehen, was ansteht. Installiert nichts. (Vorgabe)
  --aktualisieren   Updates installieren, vorher je Quelle eine Rückfrage.
  -y, --ja          Ohne Rückfrage installieren. Firmware wird dabei NIE
                    installiert, sie braucht immer eine ausdrückliche Zusage.
  --keine-farbe     Ausgabe ohne Farben (auch über NO_COLOR=1).
  --sprache de|en   Sprache erzwingen (sonst nach LANG).
  -h, --hilfe       Diese Hilfe.
  --version         Version anzeigen.
EOF
    else
        cat <<'EOF'
MelucioLabs Update Manager for Linux and macOS

Usage:
  update-manager.sh [--check | --update] [-y] [--no-color]

  --check           Show what is pending. Installs nothing. (default)
  --update          Install updates, asking once per source.
  -y, --yes         Install without asking. Firmware is NEVER installed
                    this way, it always needs an explicit yes.
  --no-color        Plain output (also via NO_COLOR=1).
  --lang de|en      Force the language (default: from LANG).
  -h, --help        This help.
  --version         Show the version.
EOF
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --pruefen|--prüfen|--check) MODUS=pruefen ;;
        --aktualisieren|--update) MODUS=aktualisieren ;;
        -y|--ja|--yes) JA=1 ;;
        --keine-farbe|--no-color) FARBE=nein ;;
        --sprache|--lang)
            shift
            case "${1:-}" in
                de) SPRACHE=de ;;
                en) SPRACHE=en ;;
                *) echo "--sprache de|en" >&2; exit 2 ;;
            esac ;;
        -h|--hilfe|--help) hilfe; exit 0 ;;
        --version) echo "update-manager.sh $UM_VERSION"; exit 0 ;;
        *)
            printf '%s\n' "$(L "Unbekannte Option: $1" "Unknown option: $1")" >&2
            hilfe >&2
            exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Farben: nur an einem Terminal, nie in einer Datei oder Pipe.
# Kein Blau: auf dunklen Terminals kaum lesbar. Cyan, Gruen, Gelb, Rot, Fett.
# ---------------------------------------------------------------------------
if [ "$FARBE" = auto ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    F_FETT=$(printf '\033[1m')
    F_OK=$(printf '\033[32m')
    F_WARN=$(printf '\033[33m')
    F_FEHLER=$(printf '\033[31m')
    F_KOPF=$(printf '\033[1;36m')
    F_AUS=$(printf '\033[0m')
else
    F_FETT=""; F_OK=""; F_WARN=""; F_FEHLER=""; F_KOPF=""; F_AUS=""
fi

kopf()    { printf '\n%s== %s ==%s\n' "$F_KOPF" "$1" "$F_AUS"; }
info()    { printf '   %s\n' "$1"; }
gut()     { printf '   %s%s%s\n' "$F_OK" "$1" "$F_AUS"; }
warnung() { printf '   %s%s%s\n' "$F_WARN" "$1" "$F_AUS"; }
fehler()  { printf '   %s%s%s\n' "$F_FEHLER" "$1" "$F_AUS"; }

hat() { command -v "$1" >/dev/null 2>&1; }

TMPD=$(mktemp -d 2>/dev/null || mktemp -d -t updatemanager)
trap 'rm -rf "$TMPD"' EXIT
trap 'exit 130' INT TERM
FEHLERDATEI="$TMPD/stderr"

# Letzte Zeile der Fehlerausgabe, fuer eine kurze Begruendung.
letzte_fehlerzeile() {
    if [ -s "$FEHLERDATEI" ]; then
        grep -v '^[[:space:]]*$' "$FEHLERDATEI" | tail -n 1
    fi
}

# ---------------------------------------------------------------------------
# Root nur fuer einzelne Schritte
# ---------------------------------------------------------------------------
IST_ROOT=0
[ "$(id -u 2>/dev/null || echo 1)" = 0 ] && IST_ROOT=1

als_root() {
    if [ "$IST_ROOT" = 1 ]; then
        "$@"
        return $?
    fi
    if ! hat sudo; then
        printf '%s\n' "$(L 'sudo fehlt, dieser Schritt braucht Administratorrechte' 'sudo is missing, this step needs administrator rights')" >"$FEHLERDATEI"
        return 126
    fi
    if [ -t 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            info "$(L "Administratorrechte nötig für: $*" "Administrator rights needed for: $*")"
        fi
        sudo "$@"
    else
        # Ohne Terminal kann sudo nicht nach dem Passwort fragen und bliebe
        # haengen. -n scheitert dann sofort und sauber.
        sudo -n "$@"
    fi
}

# ---------------------------------------------------------------------------
# Rueckfrage. Liest von der Standardeingabe; bei Dateiende gilt die Vorgabe.
# ---------------------------------------------------------------------------
frage() {
    # $1 Text, $2 Vorgabe (j|n)
    _vorgabe="$2"
    if [ "$_vorgabe" = j ]; then _hinweis=$(L '[J/n]' '[Y/n]'); else _hinweis=$(L '[j/N]' '[y/N]'); fi
    printf '   %s%s%s %s ' "$F_FETT" "$1" "$F_AUS" "$_hinweis"
    if ! IFS= read -r _antwort; then
        _antwort=""
        echo
    elif [ ! -t 0 ]; then
        # Antwort kam aus einer Pipe und wurde nicht mitgeschrieben
        echo "$_antwort"
    fi
    [ -z "$_antwort" ] && _antwort="$_vorgabe"
    case "$_antwort" in
        j|J|ja|Ja|JA|y|Y|yes|Yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Ergebnisliste. Indizierte Arrays (bash 3.2 kennt keine assoziativen).
#   Q_NAME    Anzeigename
#   Q_STATUS  fehlt | ok | fehler
#   Q_ANZAHL  Zahl der offenen Updates
#   Q_NOTIZ   kurzer Zusatz (z. B. "Paketlisten nicht aufgefrischt")
#   Q_TAT     leer | installiert | uebersprungen | fehler
# ---------------------------------------------------------------------------
Q_NAME=(); Q_STATUS=(); Q_ANZAHL=(); Q_NOTIZ=(); Q_TAT=(); Q_ID=()

# Rueckgabe der pruefe_*-Funktionen in globalen Variablen:
R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""

merke() {
    # $1 id, $2 Anzeigename, $3 Status
    _i=${#Q_NAME[@]}
    Q_ID[_i]="$1"
    Q_NAME[_i]="$2"
    Q_STATUS[_i]="$3"
    Q_ANZAHL[_i]="$R_ANZAHL"
    Q_NOTIZ[_i]="$R_NOTIZ"
    Q_TAT[_i]=""
}

zaehle_zeilen() {
    # Zahl der nicht leeren Zeilen in $1
    if [ -z "$1" ]; then echo 0; return; fi
    printf '%s\n' "$1" | grep -c '[^[:space:]]' || true
}

zeige_items() {
    # bis zu 15 Namen, dann "... und N weitere"
    _n=0
    _gesamt=$(zaehle_zeilen "$1")
    printf '%s\n' "$1" | while IFS= read -r _z; do
        [ -z "$_z" ] && continue
        _n=$((_n + 1))
        if [ "$_n" -le 15 ]; then printf '     - %s\n' "$_z"; fi
    done
    if [ "$_gesamt" -gt 15 ]; then
        info "  $(L "… und $((_gesamt - 15)) weitere" "… and $((_gesamt - 15)) more")"
    fi
}

# ---------------------------------------------------------------------------
# Pruefen je Quelle. Rueckgabe: 0 = geprueft, 1 = Fehler.
# Aufgerufen werden sie ueber ihren Namen ("pruefe_$q_id"); die Freigabe
# SC2329 dafuer steht deshalb ganz oben im Kopf.
# ---------------------------------------------------------------------------

# apt-get update einmal, auch wenn apt und mintupdate beide gefragt werden.
APT_AUFGEFRISCHT=""
apt_auffrischen() {
    if [ -n "$APT_AUFGEFRISCHT" ]; then [ "$APT_AUFGEFRISCHT" = ja ]; return $?; fi
    if als_root apt-get update -qq >/dev/null 2>"$FEHLERDATEI"; then
        APT_AUFGEFRISCHT=ja; return 0
    fi
    APT_AUFGEFRISCHT=nein; return 1
}

pruefe_apt() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    if ! apt_auffrischen; then
        R_NOTIZ=$(L 'Paketlisten nicht aufgefrischt, Stand vom letzten apt update' 'package lists not refreshed, showing the last known state')
    fi
    _aus=$(LC_ALL=C apt list --upgradable 2>"$FEHLERDATEI") || return 1
    R_ITEMS=$(printf '%s\n' "$_aus" | grep '\[upgradable from' | sed 's|/.*||')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_mint() {
    # mintupdate-cli beachtet Mints eigene Regeln (Sperrliste, Umgang mit
    # Kernel-Updates), die apt nicht kennt. Die Paketlisten frischt apt auf,
    # mintupdate liest danach nur.
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    if ! apt_auffrischen; then
        R_NOTIZ=$(L 'Paketlisten nicht aufgefrischt, Stand vom letzten apt update' 'package lists not refreshed, showing the last known state')
    fi
    _aus=$(mintupdate-cli list 2>"$FEHLERDATEI") || return 1
    # Zeilenform: "<typ> <quellpaket> <version>"
    R_ITEMS=$(printf '%s\n' "$_aus" | awk 'NF>=2 {print $2}')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_dnf() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    _aus=$(dnf -q check-update 2>"$FEHLERDATEI"); _rc=$?
    case "$_rc" in
        0) return 0 ;;
        100)
            R_ITEMS=$(printf '%s\n' "$_aus" | awk '/^Obsoleting/ {exit} NF==3 && $1 ~ /\./ {print $1}')
            R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
            return 0 ;;
        *) return 1 ;;
    esac
}

pruefe_pacman() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    if hat checkupdates; then
        # checkupdates (pacman-contrib) frischt eine KOPIE der Datenbank auf
        # und braucht deshalb kein root. `pacman -Sy` waere ein halbes
        # Update und auf Arch ausdruecklich verpoent.
        _aus=$(checkupdates 2>"$FEHLERDATEI"); _rc=$?
        case "$_rc" in
            0) ;;
            2) return 0 ;;
            *) return 1 ;;
        esac
    else
        R_NOTIZ=$(L 'Datenbank nicht aufgefrischt (checkupdates aus pacman-contrib fehlt)' 'database not refreshed (checkupdates from pacman-contrib is missing)')
        _aus=$(pacman -Qu 2>"$FEHLERDATEI"); _rc=$?
        # pacman -Qu meldet "nichts gefunden" mit 1
        [ "$_rc" -ne 0 ] && [ -z "$_aus" ] && return 0
        [ "$_rc" -ne 0 ] && return 1
    fi
    R_ITEMS=$(printf '%s\n' "$_aus" | awk 'NF {print $1}')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_zypper() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    if ! als_root zypper -n -q refresh >/dev/null 2>"$FEHLERDATEI"; then
        R_NOTIZ=$(L 'Quellen nicht aufgefrischt' 'repositories not refreshed')
    fi
    _aus=$(LC_ALL=C zypper -n -q list-updates 2>"$FEHLERDATEI") || return 1
    R_ITEMS=$(printf '%s\n' "$_aus" | awk -F'|' '/^v / {gsub(/^ +| +$/, "", $3); print $3}')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_flatpak() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    _aus=$(flatpak remote-ls --updates --columns=application 2>"$FEHLERDATEI") || return 1
    R_ITEMS=$(printf '%s\n' "$_aus" | grep -v '^Application' | grep '[^[:space:]]' || true)
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_snap() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    _aus=$(LC_ALL=C snap refresh --list 2>"$FEHLERDATEI") || {
        # "All snaps up to date." kommt auf stderr, bei manchen Fassungen mit 0
        grep -qi 'up to date' "$FEHLERDATEI" && return 0
        return 1
    }
    R_ITEMS=$(printf '%s\n' "$_aus" | awk 'NR>1 && NF {print $1}' | grep -vi '^all$' || true)
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_fwupd() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    # refresh: 0 = aufgefrischt, 2 = war schon frisch. Alles andere ist nur
    # eine Notiz, get-updates arbeitet dann mit dem vorhandenen Stand.
    fwupdmgr refresh </dev/null >/dev/null 2>"$FEHLERDATEI"; _rc=$?
    if [ "$_rc" -ne 0 ] && [ "$_rc" -ne 2 ]; then
        R_NOTIZ=$(L 'Firmware-Verzeichnis nicht aufgefrischt' 'firmware metadata not refreshed')
    fi
    _aus=$(fwupdmgr get-updates --json --no-unreported-check </dev/null 2>"$FEHLERDATEI"); _rc=$?
    if [ "$_rc" -eq 1 ] && grep -qi 'unknown option' "$FEHLERDATEI"; then
        # aeltere fwupd-Fassungen kennen die Option nicht
        _aus=$(fwupdmgr get-updates --json </dev/null 2>"$FEHLERDATEI"); _rc=$?
    fi
    case "$_rc" in
        0) ;;
        2) return 0 ;;   # nichts zu tun / keine aktualisierbaren Geraete
        *) return 1 ;;
    esac
    # Je Geraet ein "DeviceId"; der Name steht in der Geraetebeschreibung
    # davor. Kein jq noetig.
    R_ITEMS=$(printf '%s\n' "$_aus" | awk '
        /"Name"[[:space:]]*:/ { n=$0; sub(/^[^:]*:[[:space:]]*"/, "", n); sub(/",?[[:space:]]*$/, "", n) }
        /"DeviceId"[[:space:]]*:/ { print (n != "" ? n : "?"); n="" }')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_softwareupdate() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    _aus=$(softwareupdate -l 2>&1) || return 1
    R_ITEMS=$(printf '%s\n' "$_aus" | grep '^[[:space:]]*\* ' | sed 's/^[[:space:]]*\* //; s/^Label: //')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_brew() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    if [ "$IST_ROOT" = 1 ]; then
        printf '%s\n' "$(L 'Homebrew läuft nicht als root, bitte als normaler Benutzer starten' 'Homebrew refuses to run as root, start as a normal user')" >"$FEHLERDATEI"
        return 1
    fi
    if ! brew update --quiet >/dev/null 2>"$FEHLERDATEI"; then
        R_NOTIZ=$(L 'Paketliste nicht aufgefrischt' 'formula list not refreshed')
    fi
    _aus=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet 2>"$FEHLERDATEI") || return 1
    R_ITEMS="$_aus"
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

pruefe_mas() {
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    _aus=$(mas outdated 2>"$FEHLERDATEI") || return 1
    R_ITEMS=$(printf '%s\n' "$_aus" | awk 'NF {$1=""; sub(/^ /, ""); print}')
    R_ANZAHL=$(zaehle_zeilen "$R_ITEMS")
    return 0
}

# ---------------------------------------------------------------------------
# Installieren je Quelle
# ---------------------------------------------------------------------------
installiere() {
    case "$1" in
        # mintupdate-cli ruft selbst apt-get install auf und gibt dessen
        # Exit-Code NICHT weiter; ein Fehler dort steht nur in der Ausgabe.
        # --keep-configuration: eigene Aenderungen an Konfigurationsdateien
        # bleiben (ohne die Option ueberschreibt -y sie mit der neuen Fassung).
        mint)    als_root mintupdate-cli upgrade -y --keep-configuration ;;
        apt)     als_root env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold upgrade --with-new-pkgs ;;
        dnf)     als_root dnf -y upgrade ;;
        pacman)  als_root pacman -Syu --noconfirm ;;
        zypper)  als_root zypper -n update ;;
        flatpak) flatpak update -y --noninteractive ;;
        snap)    als_root snap refresh ;;
        fwupd)   fwupdmgr update ;;
        softwareupdate) als_root softwareupdate -i -a ;;
        brew)    brew upgrade ;;
        mas)     mas upgrade ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------
BETRIEBSSYSTEM=$(uname -s 2>/dev/null || echo unbekannt)

systemname() {
    if [ "$BETRIEBSSYSTEM" = Darwin ]; then
        echo "macOS $(sw_vers -productVersion 2>/dev/null)"
    elif [ -r /etc/os-release ]; then
        # PRETTY_NAME ohne die Datei zu sourcen (sie ist fremder Text)
        sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -n 1
    else
        echo "$BETRIEBSSYSTEM"
    fi
}

# id | Anzeigename | Befehl, an dem die Quelle erkannt wird
if [ "$BETRIEBSSYSTEM" = Darwin ]; then
    QUELLEN="softwareupdate|macOS softwareupdate|softwareupdate
brew|Homebrew|brew
mas|Mac App Store (mas)|mas"
else
    QUELLEN="mint|Linux Mint (mintupdate)|mintupdate-cli
apt|apt|apt-get
dnf|dnf|dnf
pacman|pacman|pacman
zypper|zypper|zypper
flatpak|Flatpak|flatpak
snap|Snap|snap
brew|Homebrew|brew
fwupd|$(L 'Firmware/BIOS (fwupd)' 'Firmware/BIOS (fwupd)')|fwupdmgr"
fi

printf '%s%s%s %s\n' "$F_FETT" "MelucioLabs Update-Manager" "$F_AUS" "$UM_VERSION"
info "$(systemname)"
if [ "$MODUS" = pruefen ]; then
    info "$(L 'Modus: nur prüfen, es wird nichts installiert.' 'Mode: check only, nothing will be installed.')"
else
    info "$(L 'Modus: aktualisieren.' 'Mode: update.')"
fi

HAT_MINT=0
# Die Liste kommt ueber Kanal 3, nicht ueber die Standardeingabe: Sonst
# saehe sudo darin kein Terminal und koennte nicht nach dem Passwort fragen.
while IFS='|' read -r q_id q_name q_befehl <&3; do
    [ -z "$q_id" ] && continue
    R_ANZAHL=0; R_ITEMS=""; R_NOTIZ=""
    : >"$FEHLERDATEI"

    # Auf Mint uebernimmt mintupdate die apt-Pakete. apt zusaetzlich zu
    # zeigen, hiesse dieselben Pakete zweimal zu zaehlen.
    if [ "$q_id" = apt ] && [ "$HAT_MINT" = 1 ]; then continue; fi
    if [ "$q_id" = apt ] && ! hat apt; then merke apt "$q_name" fehlt; continue; fi

    if ! hat "$q_befehl"; then
        merke "$q_id" "$q_name" fehlt
        continue
    fi

    kopf "$q_name"
    if "pruefe_$q_id"; then
        if [ "$q_id" = mint ]; then HAT_MINT=1; fi
        [ -n "$R_NOTIZ" ] && warnung "$R_NOTIZ"
        if [ "$R_ANZAHL" -eq 0 ]; then
            gut "$(L 'Alles aktuell.' 'Everything is up to date.')"
        else
            info "$(L "$R_ANZAHL Updates verfügbar:" "$R_ANZAHL updates available:")"
            zeige_items "$R_ITEMS"
        fi
        merke "$q_id" "$q_name" ok
    else
        _grund=$(letzte_fehlerzeile)
        if [ "$q_id" = mint ]; then
            # mintupdate gescheitert: auf apt zurueckfallen, damit die
            # Pakete nicht einfach aus der Anzeige verschwinden.
            warnung "$(L 'mintupdate-cli meldet einen Fehler, es wird apt verwendet.' 'mintupdate-cli failed, falling back to apt.')"
            [ -n "$_grund" ] && info "$_grund"
            R_NOTIZ=$(L 'Fehler, ersetzt durch apt' 'failed, replaced by apt')
            merke mint "$q_name" fehler
            continue
        fi
        fehler "$(L 'Prüfung fehlgeschlagen.' 'Check failed.')"
        [ -n "$_grund" ] && info "$_grund"
        R_NOTIZ="$_grund"
        merke "$q_id" "$q_name" fehler
    fi
done 3<<EOF
$QUELLEN
EOF

# ---------------------------------------------------------------------------
# Installieren
# ---------------------------------------------------------------------------
if [ "$MODUS" = aktualisieren ]; then
    _i=0
    while [ "$_i" -lt "${#Q_NAME[@]}" ]; do
        if [ "${Q_STATUS[$_i]}" = ok ] && [ "${Q_ANZAHL[$_i]}" -gt 0 ]; then
            _id="${Q_ID[$_i]}"
            _name="${Q_NAME[$_i]}"
            _n="${Q_ANZAHL[$_i]}"
            kopf "$(L "$_name: installieren" "$_name: install")"
            _los=0
            if [ "$_id" = fwupd ]; then
                # Firmware NIE ohne ausdrueckliche Zusage, auch nicht mit -y.
                warnung "$(L 'Firmware-Update (BIOS/UEFI oder Geräte-Firmware).' 'Firmware update (BIOS/UEFI or device firmware).')"
                warnung "$(L 'Vorher das Netzteil anschließen. Danach ist ein Neustart nötig;' 'Connect the power supply first. A restart is required afterwards;')"
                warnung "$(L 'während des Neustarts das Gerät nicht ausschalten.' 'do not switch the device off while it restarts.')"
                if [ "$JA" = 1 ]; then
                    info "$(L 'Mit -y wird Firmware nicht installiert. Dafür ohne -y starten.' 'Firmware is not installed with -y. Run again without -y.')"
                elif frage "$(L "$_n Firmware-Update(s) jetzt installieren?" "Install $_n firmware update(s) now?")" n; then
                    _los=1
                fi
            elif [ "$JA" = 1 ]; then
                _los=1
            elif frage "$(L "$_n Updates installieren?" "Install $_n updates?")" j; then
                _los=1
            fi

            if [ "$_los" = 1 ]; then
                : >"$FEHLERDATEI"
                if installiere "$_id"; then
                    Q_TAT[_i]=installiert
                    gut "$(L 'Fertig.' 'Done.')"
                else
                    Q_TAT[_i]=fehler
                    fehler "$(L 'Installation fehlgeschlagen.' 'Installation failed.')"
                    _grund=$(letzte_fehlerzeile)
                    [ -n "$_grund" ] && info "$_grund"
                fi
            else
                Q_TAT[_i]=uebersprungen
                info "$(L 'Übersprungen.' 'Skipped.')"
            fi
        fi
        _i=$((_i + 1))
    done
fi

# ---------------------------------------------------------------------------
# Zusammenfassung
# ---------------------------------------------------------------------------
kopf "$(L 'Zusammenfassung' 'Summary')"
FEHLER_GESAMT=0
OFFEN_GESAMT=0
_i=0
while [ "$_i" -lt "${#Q_NAME[@]}" ]; do
    _name="${Q_NAME[$_i]}"
    _n="${Q_ANZAHL[$_i]}"
    case "${Q_STATUS[$_i]}" in
        fehlt)
            _text=$(L 'nicht vorhanden' 'not available'); _farbe="" ;;
        fehler)
            _text=$(L 'Fehler' 'error'); _farbe="$F_FEHLER"
            FEHLER_GESAMT=$((FEHLER_GESAMT + 1)) ;;
        ok)
            if [ "$_n" -eq 1 ]; then
                _text=$(L '1 Update' '1 update')
            else
                _text=$(L "$_n Updates" "$_n updates")
            fi
            if [ "$_n" -eq 0 ]; then _farbe="$F_OK"; else _farbe="$F_WARN"; fi
            case "${Q_TAT[$_i]}" in
                installiert)   _text="$_text, $(L 'installiert' 'installed')"; _farbe="$F_OK" ;;
                uebersprungen) _text="$_text, $(L 'übersprungen' 'skipped')"
                               OFFEN_GESAMT=$((OFFEN_GESAMT + _n)) ;;
                fehler)        _text="$_text, $(L 'Fehler beim Installieren' 'installation failed')"; _farbe="$F_FEHLER"
                               FEHLER_GESAMT=$((FEHLER_GESAMT + 1)) ;;
                *)             OFFEN_GESAMT=$((OFFEN_GESAMT + _n)) ;;
            esac ;;
    esac
    printf '   %-34s %s%s%s\n' "$_name" "$_farbe" "$_text" "$F_AUS"
    [ -n "${Q_NOTIZ[_i]}" ] && printf '   %-34s (%s)\n' "" "${Q_NOTIZ[_i]}"
    _i=$((_i + 1))
done

echo
if [ "$MODUS" = pruefen ] && [ "$OFFEN_GESAMT" -gt 0 ]; then
    info "$(L "Installieren mit:  $0 --aktualisieren" "To install:  $0 --update")"
fi

[ "$FEHLER_GESAMT" -gt 0 ] && exit 1
exit 0
