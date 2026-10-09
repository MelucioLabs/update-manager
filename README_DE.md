# Universal Update Manager

Deutsche Version | **[English Version](README.md)**

---

**Plattform:** Windows 10/11
**Sprache:** PowerShell

> Dieses Projekt wurde mit KI-Unterstützung (Claude) entwickelt und dient auch als Lernprojekt zum besseren Verständnis von PowerShell-Automatisierung.

---

## Beschreibung

Ein umfassender Windows-Update-Manager, der Updates aus mehreren Quellen in einem einzigen Tool mit Hardware-Auto-Erkennung, flexibler Konfiguration, lautlosem Hintergrundmodus und Windows-Aufgabenplanung zusammenfasst.

---

## Features

### Multi-Quellen Update-Verwaltung:
- **Windows Update** - Offizielle Microsoft-Updates (inkl. optionale Treiber-Updates)
- **Winget** - Microsoft Paketmanager
- **Chocolatey** - Community-Paketmanager
- **Microsoft Store** - UWP-App Updates (öffnet den Store zur manuellen Bestätigung)

### Hardware-Auto-Erkennung:
- **CPU-Hersteller** - Intel, AMD
- **GPU-Hersteller** - NVIDIA (App + GeForce Experience Fallback), AMD, Intel
- **Mainboard** - MSI Center Unterstützung
- **Automatische Treiber-Auswahl** - Aktualisiert nur relevante Hardware-Hersteller

### Silent Mode (Hintergrund-Modus):
- Führt Winget + Chocolatey vollständig im Hintergrund aus (keine interaktiven Abfragen)
- **Angeheftete Pakete** (von Winget als "explizite Zielgruppenadressierung" markiert) werden automatisch einzeln per `--id` aktualisiert
- **Internet-Retry:** Wartet bis zu 2,5 Minuten auf eine Internetverbindung nach dem Hochfahren (5 Versuche à 30s)
- **Lock-File-Schutz:** Verhindert parallele Silent-Mode-Läufe bei mehreren Task-Triggern
- Überspringt bei bereits erfolgtem Update am gleichen Tag (Doppellauf-Schutz)
- Detailliertes Logging: Zeigt welche Pakete tatsächlich aktualisiert wurden (Name + Anzahl)
- Kann direkt über den Parameter `-SilentMode` aufgerufen werden

### Automatische Planung (Aufgabenplanung):
- Erstellt einen Windows-Aufgabenplaner-Eintrag für vollautomatische stille Updates
- **Doppelter Trigger:** Läuft täglich zu einer festgelegten Uhrzeit UND 2 Minuten nach jedem Login
- Login-Trigger holt verpasste Ausführungen nach (z. B. wenn der PC zur geplanten Zeit aus war)
- Überspringt bei bereits erfolgtem Lauf am gleichen Tag
- Vorhandene Tasks direkt aus dem Menü anzeigen, bearbeiten und löschen

### Mehrsprachigkeit:
- **Automatische Spracherkennung** anhand der Windows-Systemsprache
- Deutsch (`de`) und Englisch (alle anderen Sprachen) unterstützt
- Keine manuelle Sprachauswahl nötig

### Konfiguration:
- **JSON-basiert** - Einfach anzupassen (`update-config.json`)
- **Flexibel** - Komponenten einzeln aktivieren/deaktivieren
- **KISS-Prinzip** - Nur Einstellungen die tatsächlich genutzt werden

---

## Open Source und Installation

Der Update-Manager ist **Open Source unter der GPL-3.0** (siehe unten). Das
öffentliche Repository ist `github.com/MelucioLabs/update-manager`; es ist ein
Spiegel dieses Ordners, die Hauptquelle bleibt das MelucioLabs-Monorepo.

**Das Zielbild, für alle, die keine Konsole anfassen wollen:**

1. Das Setup einmal von `meluciolabs.de/update` herunterladen.
2. Ausführen. Es installiert nach `C:\Program Files\MelucioLabs Update-Manager`,
   legt einen Eintrag im Startmenü an, auf Wunsch eine Verknüpfung auf dem
   Desktop und die nächtliche Prüfung im Hintergrund (Aufgabenplanung).
3. Danach aktualisiert sich der Manager selbst über die GitHub-Releases.

**Stand:** Das Installer-Skript (`installer/update-manager.iss`) und der
Release-Workflow sind vorbereitet. **Signierte Setups gibt es noch nicht**;
die Code-Signatur über die SignPath Foundation ist geplant. Bis dahin warnt
Windows SmartScreen vor einem unbekannten Herausgeber. Das Fenster fragt höchstens
einmal am Tag bei GitHub nach einer neuen Fassung; der Knopf „Neue Version
installieren“ ist gebaut, aber AUS, bis das Setup signiert ist
(`SELBST-UPDATE.md`). Für Linux und macOS
gibt es ein eigenes Skript in `linux/` (siehe `linux/LIESMICH.md`).

Eigene Einstellungen gehören in `update-config.local.json` neben den Skripten;
das Setup fasst diese Datei nie an, sie überlebt also jedes Update.

---

## Installation & Nutzung

### Voraussetzungen:
- Windows 10/11
- PowerShell 5.1 oder höher
- Administrator-Rechte
- PSWindowsUpdate Modul (wird bei Bedarf automatisch installiert)

### Schnellstart:
1. Alle Dateien in einen Ordner herunterladen
2. Doppelklick auf `universal-update-manager.bat`
3. Admin-Erhöhung bestätigen
4. Option aus Menü wählen

### Manuelle Ausführung:
```powershell
# Als Administrator ausführen
.\universal-update-manager.ps1

# Direkt im Silent Mode starten (z. B. via Aufgabenplanung)
.\universal-update-manager.ps1 -SilentMode
```

---

## Menü-Übersicht

| # | Option | Beschreibung |
|---|--------|--------------|
| 1 | Vollständiges Update | Alle Quellen + Hardware-Hersteller |
| 2 | Nur Winget | Winget Paket-Updates |
| 3 | Nur Chocolatey | Chocolatey Paket-Updates |
| 4 | Nur Windows Update | Microsoft-Updates + Treiber |
| 5 | Microsoft Store | Öffnet Store für UWP-Updates |
| 6 | Hardware-Hersteller | NVIDIA / AMD / Intel / MSI Tools |
| 7 | Silent Mode | Hintergrund-Update (Winget + Choco) |
| 8 | Auto-Update Setup | Aufgabenplanung erstellen/bearbeiten/löschen |
| 9 | System-Info | Hardware & installierte Tools Übersicht |
| L | Log anzeigen | Letzte 50 Zeilen der Log-Datei |

> Die meisten Eingaben erfolgen per Einzeltastendruck (kein Enter nötig). Nur die Uhrzeiteingabe bei der Aufgabenplanung benötigt Enter.

---

## Konfiguration

### update-config.json Struktur:

```json
{
  "updateSources": {
    "winget": { "enabled": true, "autoAccept": false, "timeoutSeconds": 300 },
    "chocolatey": { "enabled": true, "autoAccept": false, "timeoutSeconds": 90 },
    "windowsUpdate": { "enabled": true, "includeDrivers": true, "includeOptional": false },
    "microsoftStore": { "enabled": true }
  },
  "hardwareVendors": {
    "nvidia": { "enabled": true },
    "amd": { "enabled": true },
    "intel": { "enabled": true },
    "msi": { "enabled": true }
  },
  "silentMode": {
    "scheduledTaskName": "UpdateManager-SilentMode"
  }
}
```

### Komponenten aktivieren/deaktivieren:
- `enabled` auf `true` oder `false` setzen
- Konfiguration bleibt über Ausführungen hinweg erhalten

---

## Treiber-Updates

| Hersteller | Tool | Hinweise |
|------------|------|----------|
| **NVIDIA** | NVIDIA App (Priorität) oder GeForce Experience | Auto-erkannt |
| **AMD** | Radeon Software | Auto-erkannt |
| **Intel** | Intel Driver & Support Assistant | Auto-erkannt |
| **MSI** | MSI Center | Mainboard auto-erkannt |

---

## Aufgabenplanung Details

Das Auto-Update Setup (Menüpunkt 8) erstellt einen Aufgabenplaner-Task mit zwei Triggern:

- **Täglicher Trigger** – läuft zur festgelegten Uhrzeit
- **AtLogOn-Trigger** – läuft 2 Minuten nach jedem Login

Der Login-Trigger stellt sicher, dass verpasste Ausführungen nachgeholt werden, wenn der PC zur geplanten Zeit ausgeschaltet war.
Eine Log-basierte Prüfung verhindert, dass der Task mehr als einmal pro Tag ausgeführt wird.

Der Task läuft unter dem eigenen Benutzerkonto mit erhöhten Rechten und erfordert **keine** Passwortabfrage.

**Die Uhrzeit lässt sich auch im Fenster setzen** (seit 22.09.2026): unten im
Block „Was soll geprüft werden?" steht „Nächtlich um HH:MM · Übernehmen", dazu
eine Zeile mit dem nächsten und letzten Lauf. Der Umweg über das Konsolenmenü
entfällt. Das Fenster rechnet dabei nichts selbst aus — es fragt den Kern
(`-AufgabeStatus`) und lässt ihn eintragen (`-AufgabeZeit HH:MM`).

**Der Task zeigt auf die Datei, aus der er eingerichtet wurde.** Wird der Ordner später verschoben oder kopiert, startet die Aufgabenplanung weiter die alte Datei — und dann läuft nachts ein anderer Stand als tagsüber von Hand. Genau das war zwischen dem 21. und 22.09.2026 der Fall (466 Zeilen Unterschied, und der nächtliche Lauf war der ältere). Der Manager prüft das deshalb bei jedem Start selbst und meldet eine Abweichung in Protokoll und Konsole; **ändern tut er nichts** — eine Aufgabe umzuhängen ist eine Entscheidung. Richtigstellen: Menüpunkt 8 aus der Datei aufrufen, die künftig laufen soll.

---

## Eigene Einstellungen und Meldungen

Zwei Dateien nebeneinander:

| Datei | gehört |
|---|---|
| `update-config.json` | zum Werkzeug, liegt im Repo |
| `update-config.local.json` | der **Maschine**, wird nicht versioniert |

Die lokale Fassung gewinnt, abschnittweise — was dort nicht steht, bleibt wie
geliefert. So überlebt eine eigene Einstellung den nächsten `git pull`, und das
Werkzeug lässt sich weitergeben, ohne vorher aufzuräumen.

**Meldung bei einem nächtlichen Lauf mit Fehlern** (und nur dann; ein Lauf, der
drei Programme aktualisiert hat, ist kein Ereignis):

```json
{
  "benachrichtigung": {
    "enabled": true,
    "url": "https://ntfy.example.org/<topic>",
    "authDatei": "%USERPROFILE%\.ntfy-auth"
  }
}
```

Die Zugangsdatei enthält **eine** Zeile `benutzer:passwort` und gehört nicht ins
Repo. Fehlt sie oder fehlt die Adresse, sagt der Manager das im Protokoll,
statt stillschweigend nichts zu tun — eine abgeschaltete Funktion, die so tut
als liefe sie, ist schlimmer als gar keine.

---

## Probe (Test ohne Nebenwirkung)

```
pwsh -File probe.ps1
```

Prüft in Sekunden und ohne Administratorrechte: Syntax beider Skripte, das
BOM (ohne das liest Windows PowerShell 5.1 die Umlaute kaputt), ob jeder
Auftragsname des Fensters im Kern vorkommt, ob jeder Textschlüssel in beiden
Sprachtabellen steht, ob sich das Fenster hell **und** dunkel aufbauen lässt,
und ob die Konfiguration lesbar ist. Gehört vor jede Weitergabe und hinter
jede Änderung von Hand.

Das Fenster selbst kennt dafür zwei Schalter:
`-NurPruefen` (baut auf, öffnet nichts) und `-Abbild <datei.png>`
(zeichnet das Fenster in eine Datei, ohne es zu öffnen).

---

## Hell und dunkel

Das Fenster folgt der Windows-Einstellung **App-Modus**; von Hand geht
`-Erscheinung hell` oder `-Erscheinung dunkel`. Die Farben sind gemessen, nicht
geschätzt: Fließtext erreicht in beiden Fassungen mindestens 4,5:1. Dabei fiel
auf, dass weiße Schrift auf dem Marken-Lila #7C6AF5 nur 4,01:1 erreicht — die
Knopffläche ist deshalb #5B47D6 (6,33:1), das Marken-Lila bleibt für Flächen
und Ränder.

---

## Log-Dateien

Logs werden gespeichert in:
```
C:\ProgramData\UpdateManager\universal-update-manager.log
```

> Dieser Pfad ist für alle Benutzerkonten zugänglich, auch im Kontext der Aufgabenplanung.

Das Protokoll hält **7 Tage** (seit dem 03.10.2026). Bei jedem Start fallen die
Zeilen weg, die älter sind; Altdateien daneben (`.ansi-sicherung`, `.log.1`,
datierte Archive) verschwinden nach derselben Frist. Vorher gab es zwei
Rotationen nach Größe nebeneinander (1 MB und 5 MB), und keine von beiden
sagte, wie weit das Protokoll zurückreicht.

Ein stiller Lauf endet mit `[SILENT-DONE]`, ein gescheiterter mit
`[SILENT-FAILED]`. Nur der erste gilt als „heute schon gelaufen“; einen
gescheiterten holt der nächste Auslöser der Aufgabe nach.

**Was der nächtliche Lauf getan hat, steht seit dem 22.09.2026 im Fenster** —
eine Zeile unter der Hardware („Letzter stiller Lauf: … — 3 Updates"), samt
Fehlerzahl, wenn es welche gab. Ein Lauf ohne Fenster ist sonst unsichtbar, bis
jemand von sich aus das Protokoll öffnet.

---

## Datei-Struktur

```
update-manager/
├── universal-update-manager.bat    # Starter (Admin-Erhöhung), Konsolenmenü
├── universal-update-manager.ps1    # Haupt-Script
├── update-manager-gui.bat          # Starter für das Fenster (Admin-Erhöhung)
├── update-manager-gui.ps1          # Fenster (WPF)
├── update-config.json              # Vorgabe-Konfiguration
├── update-config.local.json        # Eigene Einstellungen (nicht ausgeliefert, übersteht Updates)
├── probe.ps1                       # Test ohne Nebenwirkung
├── diagnose-silent.ps1             # Diagnose für den Silent Mode
├── installer/update-manager.iss    # Inno-Setup-Skript
├── linux/update-manager.sh         # Linux und macOS
├── .github/workflows/release.yml   # Build (wirkt im öffentlichen Repo)
├── LICENSE                         # GPL-3.0
├── NOTICE                          # Urheber, Lizenz, Marke
├── README.md                       # Englische Dokumentation
└── README_DE.md                    # Deutsche Dokumentation
```

---

## Changelog

### v3.1 (26.02.2026)
- **Silent Mode Fix:** Winget-Updates werden jetzt zuverlässig installiert (auch über Aufgabenplanung)
- **Angeheftete Pakete:** Werden automatisch einzeln per `winget upgrade --id` aktualisiert
- **Internet-Retry:** Wartet nach dem Hochfahren bis zu 2,5 Min. auf Internetverbindung
- **Lock-File:** Verhindert parallele Silent-Mode-Läufe bei Doppel-Trigger
- **Einzeltastendruck:** Menüauswahl und Ja/Nein-Abfragen ohne Enter-Taste
- **Detailliertes Logging:** Zeigt welche Pakete tatsächlich aktualisiert wurden
- Winget-Output-Parser für deutsche und englische Locale verbessert

### v3.0 (24.02.2026)
- Silent Mode hinzugefügt (Winget + Chocolatey im Hintergrund, keine Abfragen)
- Aufgabenplanung mit Doppel-Trigger (Täglich + AtLogOn mit 2 Min. Verzögerung)
- Doppellauf-Schutz: Überspringt wenn bereits heute gelaufen
- Automatische DE/EN Spracherkennung anhand der Systemsprache
- Log-Pfad nach `C:\ProgramData\UpdateManager` verschoben (kontenübergreifend)
- Winget `--include-unknown` entfernt (sicherer für den Alltagsbetrieb)
- Winget Silent Mode Timeout auf 300s erhöht
- Menü auf 10 Punkte umstrukturiert
- Aufgabenplanung Status/Bearbeiten/Löschen in Menüpunkt 8 integriert
- UTF-8 mit BOM für korrekte Sonderzeichen-Anzeige in PowerShell 5.1
- Internetverbindungs-Prüfung verbessert (TCP-basiert, schneller)

### v2.2 (23.11.2025)
- NVIDIA App Support hinzugefügt (ersetzt GeForce Experience)
- Hardware-Vendor `enabled`-Flags werden jetzt beachtet
- Config aufgeräumt (KISS-Prinzip)
- Log-Pfad nach `%LOCALAPPDATA%\UpdateManager` verschoben
- Vereinfachte Voraussetzungsprüfung

### v2.1 (02.11.2025)
- Config-Settings werden jetzt tatsächlich genutzt
- PSWindowsUpdate Modul-Check beim Start
- Sonderzeichen-Fixes
- Verbesserte Fehlerbehandlung

---

## Autor

**David Vaupel**
Windows-Automatisierungs-Enthusiast | PowerShell-Lernender

---

## Lizenz

Copyright (C) 2025-2026 MelucioLabs / David Vaupel

Dieses Programm ist freie Software: Es darf unter den Bedingungen der **GNU
General Public License, Version 3 oder (nach Wahl) jeder späteren Version**
weitergegeben und verändert werden (`SPDX-License-Identifier:
GPL-3.0-or-later`). Es wird in der Hoffnung verbreitet, dass es nützlich ist,
aber OHNE JEDE GEWÄHRLEISTUNG. Maßgeblich ist der englische Originaltext in
[`LICENSE`](LICENSE).

Kurz gesagt: benutzen, verändern, weitergeben. Wer eine veränderte Fassung
weitergibt, muss deren Quelltext unter derselben Lizenz offenlegen.

### Name und Marke

Die Lizenz gilt für den Quelltext. Name und Marke „MelucioLabs“ (samt Logos und
Markenfarben) gehören nicht zur freien Lizenz. Veränderte Fassungen dürfen
unter der Lizenz weitergegeben werden, aber nicht unter diesem Namen oder dieser
Marke in einer Weise, die den Eindruck erweckt, sie stammten von MelucioLabs.

---

**Status:** Produktionsreif
**Letzte Aktualisierung:** Februar 2026
