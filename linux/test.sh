#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 MelucioLabs / David Vaupel
#
# Prueft die Erkennung von update-manager.sh mit gefaelschten Befehlen.
#
# Jeder Fall bekommt ein eigenes bin-Verzeichnis, und PATH zeigt NUR
# dorthin. Darin liegen Verweise auf die wenigen echten Werkzeuge, die das
# Skript braucht (grep, sed, awk, ...), plus die Faelschungen des Falls.
# So fehlt ein echtes apt auf dem Pruefrechner nicht nur scheinbar, sondern
# wirklich.
#
# Nichts hier installiert oder aendert etwas am System. Aufruf: ./test.sh

set -u

HIER=$(cd "$(dirname "$0")" && pwd)
SKRIPT="$HIER/update-manager.sh"
BASH_BIN=$(command -v bash)
ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT

GUT=0
SCHLECHT=0

ok()   { GUT=$((GUT + 1)); printf '  ok    %s\n' "$1"; }
nein() { SCHLECHT=$((SCHLECHT + 1)); printf '  FEHLER %s\n' "$1"; }

enthaelt()      { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else nein "$1 (erwartet: $3)"; fi; }
enthaelt_nicht() { if printf '%s' "$2" | grep -qF -- "$3"; then nein "$1 (unerwartet: $3)"; else ok "$1"; fi; }
gleich()        { if [ "$2" = "$3" ]; then ok "$1"; else nein "$1 (ist: $2, soll: $3)"; fi; }

# Neues bin-Verzeichnis mit den echten Grundwerkzeugen.
neues_bin() {
    B="$ARBEIT/bin$1"
    rm -rf "$B"; mkdir -p "$B"
    for w in grep sed awk head tail mktemp rm uname cat env tr dirname; do
        ln -s "$(command -v "$w")" "$B/$w"
    done
    # id faelschen, damit "root oder nicht" steuerbar ist
    cat >"$B/id" <<'EOF'
#!/bin/sh
echo "${FAKE_UID:-0}"
EOF
    chmod +x "$B/id"
    LOG="$ARBEIT/log$1"
    : >"$LOG"
}

# fake NAME <<'EOF' ... EOF   legt eine Faelschung an. $LOG steht im Skript.
fake() {
    {
        echo '#!/bin/sh'
        echo "LOG='$LOG'"
        # Einfache Anfuehrungszeichen mit Absicht: die Zeile gehoert in die Faelschung.
        # shellcheck disable=SC2016
        echo 'echo "$(basename "$0" 2>/dev/null || echo "$0") $*" >>"$LOG"'
        cat
    } >"$B/$1"
    ln -sf "$(command -v basename)" "$B/basename" 2>/dev/null
    chmod +x "$B/$1"
}

# Laeuft das Skript mit PATH nur auf das bin-Verzeichnis.
lauf() {
    AUS=$(env -u LC_ALL -u LC_MESSAGES PATH="$B" LANG="${TLANG:-C}" FAKE_UID="${FAKE_UID:-0}" \
          "$BASH_BIN" "$SKRIPT" "$@" 2>&1)
    RC=$?
}

# Wiederkehrende Faelschungen
fake_apt_3() {
    fake apt <<'EOF'
if [ "$1" = list ]; then
  echo "Listing..."
  echo "firefox/noble-updates 131.0 amd64 [upgradable from: 130.0]"
  echo "libc6/noble-updates 2.39-0ubuntu8.4 amd64 [upgradable from: 2.39-0ubuntu8.3]"
  echo "tzdata/noble-updates 2026a amd64 [upgradable from: 2025b]"
fi
exit 0
EOF
    fake apt-get <<'EOF'
exit 0
EOF
}

fake_fwupd_1() {
    fake fwupdmgr <<'EOF'
case "$1" in
  refresh) exit 2 ;;
  get-updates)
    cat <<'J'
{
  "Devices" : [
    {
      "Name" : "System Firmware",
      "DeviceId" : "a45df35ac0e948ee180fe216a5f703f32dda163f",
      "Releases" : [ { "Version" : "1.2.3" } ]
    }
  ]
}
J
    exit 0 ;;
  update) exit 0 ;;
esac
exit 0
EOF
}

echo "update-manager.sh: Erkennung mit gefaelschten Befehlen"
echo

echo "Fall 1: gar nichts vorhanden"
neues_bin 1
lauf --pruefen
gleich   "Exit-Code 0" "$RC" 0
enthaelt "apt nicht vorhanden"      "$AUS" "apt                                not available"
enthaelt "Flatpak nicht vorhanden"  "$AUS" "Flatpak                            not available"
enthaelt "fwupd nicht vorhanden"    "$AUS" "Firmware/BIOS (fwupd)              not available"
enthaelt_nicht "keine Quelle geprueft" "$AUS" "== apt =="

echo "Fall 2: apt mit 3 Updates, als root"
neues_bin 2
fake_apt_3
lauf
gleich   "Exit-Code 0" "$RC" 0
enthaelt "apt zaehlt 3"             "$AUS" "apt                                3 updates"
enthaelt "Paketname angezeigt"      "$AUS" "- firefox"
enthaelt "apt-get update gelaufen"  "$(cat "$LOG")" "apt-get update -qq"
enthaelt_nicht "kein sudo als root" "$(cat "$LOG")" "sudo"
enthaelt_nicht "prueft installiert nichts" "$(cat "$LOG")" "upgrade"

echo "Fall 3: apt mit 3 Updates, als normaler Benutzer"
neues_bin 3
fake_apt_3
fake sudo <<'EOF'
[ "$1" = -n ] && shift
exec "$@"
EOF
FAKE_UID=1000 lauf
enthaelt "apt-get update ueber sudo"   "$(cat "$LOG")" "sudo -n apt-get update -qq"
enthaelt_nicht "apt list ohne sudo"    "$(cat "$LOG")" "sudo -n apt list"
enthaelt "apt zaehlt 3"                "$AUS" "3 updates"

echo "Fall 4: nicht root, sudo fehlt: Listen nicht aufgefrischt, trotzdem gezaehlt"
neues_bin 4
fake_apt_3
FAKE_UID=1000 lauf
enthaelt "Hinweis auf alten Stand"  "$AUS" "package lists not refreshed"
enthaelt "apt zaehlt trotzdem 3"    "$AUS" "3 updates"
gleich   "kein Fehler" "$RC" 0

echo "Fall 5: kein apt, Flatpak mit 2, fwupdmgr fehlt"
neues_bin 5
fake flatpak <<'EOF'
[ "$1" = remote-ls ] && { echo org.gimp.GIMP; echo org.mozilla.Thunderbird; }
exit 0
EOF
lauf
enthaelt "Flatpak zaehlt 2"         "$AUS" "Flatpak                            2 updates"
enthaelt "apt nicht vorhanden"      "$AUS" "apt                                not available"
enthaelt "fwupd nicht vorhanden"    "$AUS" "Firmware/BIOS (fwupd)              not available"

echo "Fall 6: fwupdmgr mit einem Geraet"
neues_bin 6
fake_fwupd_1
lauf
enthaelt "Firmware zaehlt 1"        "$AUS" "Firmware/BIOS (fwupd)              1 update"
enthaelt "Geraetename angezeigt"    "$AUS" "- System Firmware"

echo "Fall 7: fwupdmgr scheitert"
neues_bin 7
fake fwupdmgr <<'EOF'
echo "Failed to connect to daemon" >&2
exit 1
EOF
lauf
enthaelt "Firmware als Fehler"      "$AUS" "Firmware/BIOS (fwupd)              error"
gleich   "Exit-Code 1 bei Fehler" "$RC" 1

echo "Fall 8: --aktualisieren -y installiert apt, Firmware NICHT"
neues_bin 8
fake_apt_3
fake_fwupd_1
lauf --aktualisieren -y
enthaelt "apt-get upgrade gelaufen" "$(cat "$LOG")" "upgrade --with-new-pkgs"
enthaelt_nicht "fwupdmgr update NICHT gelaufen" "$(cat "$LOG")" "fwupdmgr update"
enthaelt "Hinweis Netzteil"         "$AUS" "power supply"
enthaelt "Hinweis -y"               "$AUS" "not installed with -y"
enthaelt "apt installiert"          "$AUS" "3 updates, installed"
enthaelt "Firmware uebersprungen"   "$AUS" "1 update, skipped"

echo "Fall 9: --aktualisieren, apt ja, Firmware nein"
neues_bin 9
fake_apt_3
fake_fwupd_1
AUS=$(printf 'j\nn\n' | env -u LC_ALL -u LC_MESSAGES PATH="$B" LANG=C FAKE_UID=0 "$BASH_BIN" "$SKRIPT" --aktualisieren 2>&1)
enthaelt "apt-get upgrade gelaufen" "$(cat "$LOG")" "upgrade --with-new-pkgs"
enthaelt_nicht "fwupdmgr update nicht gelaufen" "$(cat "$LOG")" "fwupdmgr update"

echo "Fall 10: --aktualisieren, Firmware ausdruecklich ja"
neues_bin 10
fake_fwupd_1
AUS=$(printf 'y\n' | env -u LC_ALL -u LC_MESSAGES PATH="$B" LANG=C FAKE_UID=0 "$BASH_BIN" "$SKRIPT" --aktualisieren 2>&1)
enthaelt "fwupdmgr update gelaufen" "$(cat "$LOG")" "fwupdmgr update"

echo "Fall 11: Firmware-Vorgabe ist Nein (leere Eingabe)"
neues_bin 11
fake_fwupd_1
AUS=$(printf '\n' | env -u LC_ALL -u LC_MESSAGES PATH="$B" LANG=C FAKE_UID=0 "$BASH_BIN" "$SKRIPT" --aktualisieren 2>&1)
enthaelt_nicht "Enter installiert keine Firmware" "$(cat "$LOG")" "fwupdmgr update"

echo "Fall 12: Linux Mint, mintupdate ersetzt apt"
neues_bin 12
fake_apt_3
fake mintupdate-cli <<'EOF'
if [ "$1" = list ]; then
  echo "package         firefox                                       131.0+linuxmint1"
  echo "security        libc6                                         2.39-0ubuntu8.4"
fi
exit 0
EOF
lauf
enthaelt "mintupdate zaehlt 2"      "$AUS" "Linux Mint (mintupdate)            2 updates"
enthaelt_nicht "apt nicht doppelt"  "$AUS" "apt                                3 updates"
enthaelt "Quellpaket angezeigt"     "$AUS" "- libc6"

echo "Fall 13: mintupdate scheitert, apt springt ein"
neues_bin 13
fake_apt_3
fake mintupdate-cli <<'EOF'
echo "Traceback: kaputt" >&2
exit 1
EOF
lauf
enthaelt "Mint als Fehler"          "$AUS" "Linux Mint (mintupdate)            error"
enthaelt "apt zaehlt 3"             "$AUS" "apt                                3 updates"

echo "Fall 14: dnf mit 2 Updates (Exit 100)"
neues_bin 14
fake dnf <<'EOF'
echo ""
echo "kernel.x86_64          6.10.3-200.fc40        updates"
echo "vim-minimal.x86_64     2:9.1.393-1.fc40       updates"
exit 100
EOF
lauf
enthaelt "dnf zaehlt 2"             "$AUS" "dnf                                2 updates"

echo "Fall 15: snap aktuell (Meldung auf stderr)"
neues_bin 15
fake snap <<'EOF'
echo "All snaps up to date." >&2
exit 0
EOF
lauf
enthaelt "snap 0 Updates"           "$AUS" "Snap                               0 updates"

echo "Fall 16: Deutsch nach LANG"
neues_bin 16
fake_apt_3
TLANG=de_DE.UTF-8 lauf
enthaelt "deutsche Zusammenfassung" "$AUS" "Zusammenfassung"
enthaelt "deutsch: nicht vorhanden" "$AUS" "nicht vorhanden"
enthaelt "deutsch: 3 Updates"       "$AUS" "3 Updates"

echo "Fall 17: keine Farben ohne Terminal"
ESC=$(printf '\033')
enthaelt_nicht "keine Steuerzeichen" "$AUS" "$ESC"

echo "Fall 18: falscher Aufruf"
neues_bin 18
lauf --gibtsnicht
gleich "Exit-Code 2" "$RC" 2

echo
echo "$GUT bestanden, $SCHLECHT fehlgeschlagen"
[ "$SCHLECHT" -eq 0 ]
