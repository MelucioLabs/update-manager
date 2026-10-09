# Update-Manager für Linux (und macOS)

Eine einzelne Datei, `update-manager.sh`. Sie sucht selbst zusammen, welche
Update-Quellen es auf dem Rechner gibt, zeigt an, was ansteht, und installiert
auf Wunsch. Was es nicht gibt, wird still übersprungen.

## Herunterladen und starten

```bash
# herunterladen (sobald das öffentliche Repo steht)
curl -LO https://raw.githubusercontent.com/MelucioLabs/update-manager/main/linux/update-manager.sh

# einmal ausführbar machen
chmod +x update-manager.sh

# nachsehen, was ansteht (installiert nichts)
./update-manager.sh

# installieren, mit einer Rückfrage je Quelle
./update-manager.sh --aktualisieren

# installieren ohne Rückfrage (Firmware bleibt dabei immer außen vor)
./update-manager.sh --aktualisieren -y
```

Das Skript wird als **normaler Benutzer** gestartet, nicht mit `sudo`. Nur die
Schritte, die Administratorrechte brauchen (zum Beispiel `apt-get update` und
das Installieren), laufen über `sudo`; dafür wird einmal das eigene Passwort
abgefragt.

## Was „Prüfen“ tut

`--pruefen` ist die Vorgabe und **installiert nichts**. Es

1. frischt die Paketlisten auf (`apt-get update`, dafür die Passwortabfrage;
   ohne Passwort werden die zuletzt geladenen Listen gezeigt, mit Hinweis),
2. fragt jede vorhandene Quelle, was offen ist, und listet bis zu 15 Namen,
3. zeigt am Ende eine Zusammenfassung: je Quelle „x Updates“,
   „nicht vorhanden“ oder „Fehler“.

## Erkannte Quellen

| Quelle | Befehl | Hinweis |
|---|---|---|
| Linux Mint | `mintupdate-cli` | ersetzt auf Mint die apt-Zeile und beachtet Mints Regeln (Sperrliste `/etc/mintupdate.blacklist`, Kernel-Updates). Gezählt werden Quellpakete, deshalb meist weniger als bei apt. |
| Debian, Ubuntu | `apt` | `apt list --upgradable` nach `apt-get update` |
| Fedora | `dnf` | `dnf check-update` |
| Arch | `pacman` | mit `checkupdates` (pacman-contrib), sonst Stand der lokalen Datenbank |
| openSUSE | `zypper` | `zypper list-updates` |
| Flatpak | `flatpak` | ohne Administratorrechte |
| Snap | `snap` | |
| Homebrew | `brew` | Linux und Mac, nie als root |
| Firmware/BIOS | `fwupdmgr` | siehe unten |
| macOS | `softwareupdate`, `mas` | nur auf dem Mac |

## Firmware (BIOS, UEFI, Geräte)

Firmware wird **nie ohne ausdrückliche Zusage** installiert, auch nicht mit
`-y`. Die Rückfrage steht auf „Nein“, Enter allein installiert nichts.

Vorher:

- **Netzteil anschließen.** Ein leerer Akku mitten im Schreiben kann das Gerät
  unbrauchbar machen.
- Danach ist ein **Neustart** nötig, die Firmware wird dabei eingespielt.
  Während des Neustarts das Gerät nicht ausschalten, auch wenn der Bildschirm
  eine Weile schwarz bleibt.

## Sprache und Farben

Deutsch oder Englisch nach `LANG` (`--sprache de|en` erzwingt eine). Farben nur
an einem Terminal; in eine Datei oder Pipe geschrieben kommt reiner Text,
ebenso mit `--keine-farbe` oder `NO_COLOR=1`.

## Exit-Code

`0` alles gelaufen, `1` mindestens eine Quelle mit Fehler, `2` falscher Aufruf.

## Test

`./test.sh` prüft die Erkennung mit gefälschten Befehlen (kein apt, kein
flatpak, fwupdmgr fehlt, apt mit 3 Updates, Mint, Firmware-Rückfrage, …).
Er ändert nichts am System.
