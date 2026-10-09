# Selbst-Update

Stand 08.10.2026. **Gebaut, Installieren standardmäßig AUS.** Der Code steht in
`selbst-update.ps1` (nur Funktionen) und im Kopf des Fensters
(`update-manager-gui.ps1`, Abschnitt „Neue Fassung“). Geprüft wird er von
`probe.ps1` (Abschnitt 11) gegen gespeicherte Antworten und eine Attrappe, nicht
gegen ein echtes Release: Das öffentliche Repo und das erste Release gibt es
noch nicht.

Schalter in `update-config.json` (eigene Werte in `update-config.local.json`):

| Schalter | Vorgabe | Wirkung |
| --- | --- | --- |
| `selbstUpdate.pruefen` | `true` | höchstens einmal am Tag bei GitHub fragen, Zeile „Version X ist verfügbar“ mit Link auf die Notizen und auf `meluciolabs.de/update`; lädt nichts |
| `selbstUpdate.installieren` | `false` | blendet „Neue Version installieren“ ein; **erst mit Signatur freischalten** |

Solange `$SU_SignaturAussteller` in `selbst-update.ps1` leer ist (Setup
unsigniert), verlangt der Knopf zwei Klicks („Ja, installieren“) und prüft
trotzdem die SHA-256-Summe. Steht dort ein Aussteller, startet **nie** ein
unsigniertes oder fremd signiertes Setup, auch nicht nach Bestätigung.
Der stille Lauf der Aufgabenplanung aktualisiert sich nicht selbst (siehe unten)
und fragt auch nicht nach.

Umgesetzt abweichend vom ersten Entwurf: Der Ablauf läuft in einem eigenen Faden
(Fenster steht nicht), die Datei bleibt bis zum Ende des Setups mit gesperrtem
Schreibzugriff geöffnet (kein Austausch zwischen Prüfen und Starten), geladen
wird nach `%ProgramData%\UpdateManager\setup\` (nur SYSTEM und Administratoren),
und das Fenster öffnet sich nach erfolgreichem Setup (Exit-Code 0) selbst neu.
Die gemerkte Antwort in `selbst-update.json` wird wie eine Netzantwort geprüft.

## Ziel

Wer das Setup einmal von `meluciolabs.de/update` installiert hat, muss sich um
neue Fassungen nicht mehr kümmern. Das Fenster sagt, wenn es eine neue gibt, und
installiert sie auf einen Klick.

## Ablauf

1. **Beim Start des Fensters**, im Hintergrund und nach dem Aufbau (so wie
   Hardware und Aufgabenplanung heute schon nachgeladen werden, das Fenster darf
   dabei nicht stehen):

   ```
   GET https://api.github.com/repos/MelucioLabs/update-manager/releases/latest
   Accept: application/vnd.github+json
   User-Agent: MelucioLabs-Update-Manager/<Version>
   ```

   `releases/latest` liefert nie Vorabfassungen und nie Entwürfe; `v3.2.0-rc1`
   erreicht also nur, wer es von Hand holt.
   Höchstens **einmal am Tag** fragen (Zeitpunkt in
   `%ProgramData%\UpdateManager\selbst-update.json` merken). Ohne Anmeldung
   erlaubt GitHub 60 Abfragen je Stunde und Adresse, das reicht weit.

2. **Vergleichen**: `tag_name` ohne `v` gegen `$UpdaterVersion`, als
   `[version]` (nicht als Text, sonst ist `3.10.0` kleiner als `3.9.0`).
   Vorabteile hinter `-` werden abgeschnitten.

3. **Anzeigen**: Ist die Fassung neuer, erscheint im Kopf des Fensters eine
   Zeile „Version 3.3.0 ist verfügbar“ mit dem Knopf **„Neue Version
   installieren“** und einem Link auf die Release-Notizen. Kein Aufdrängen:
   kein Dialog, der sich vor die Arbeit schiebt, und die Zeile lässt sich
   für diese Fassung ausblenden („Später“).

4. **Herunterladen**: das Asset `MelucioLabs-Update-Manager-Setup-<Version>.exe`
   und `SHA256SUMS.txt` nach `%TEMP%\UpdateManager-Setup\`.

5. **Prüfen**, bevor irgendetwas startet (siehe Sicherheit).

6. **Starten**: `Start-Process <setup.exe> -ArgumentList '/SILENT','/NORESTART'`,
   danach schließt sich das Fenster selbst. Inno Setup ersetzt die Dateien,
   die Aufgabenplanung bleibt (das Setup trägt sie nur ein, wenn sie fehlt),
   `update-config.local.json` bleibt unberührt.
   Offener Punkt: Im stillen Modus öffnet das Setup das Fenster danach nicht
   wieder (`skipifsilent`). Entweder ein eigener `[Run]`-Eintrag mit
   `Check: WizardSilent` und einem Parameter wie `/NEUSTART`, oder die
   Oberfläche startet einen kleinen Warte-Prozess, der das Fenster nach dem
   Setup wieder öffnet.

Der stille Lauf der Aufgabenplanung aktualisiert sich **nicht** selbst: Wer
nachts um vier eine neue Fassung einspielt, hat niemanden, der auf einen Fehler
reagiert. Er schreibt höchstens eine Zeile ins Protokoll, dass es eine neue
Fassung gibt.

## Sicherheit

- **Nur von GitHub, nur aus diesem Repo.** Die Abfrage-Adresse ist fest im
  Code, nicht in der Konfiguration. Heruntergeladen wird nur, wenn
  `browser_download_url` mit
  `https://github.com/MelucioLabs/update-manager/releases/download/` beginnt.
  Weiterleitungen auf `objects.githubusercontent.com` sind normal; geprüft wird
  die Adresse aus der API-Antwort, nicht das Ende der Weiterleitung.
- **Nur HTTPS**, TLS 1.2 ausdrücklich einschalten
  (`[Net.ServicePointManager]::SecurityProtocol` unter Windows PowerShell 5.1).
- **Prüfsumme**: SHA-256 des Setups muss zu `SHA256SUMS.txt` aus demselben
  Release passen. Das schützt vor einem kaputten Download, nicht vor einem
  kompromittierten Release; dafür ist der nächste Punkt da.
- **Signatur, sobald signiert wird** (SignPath Foundation):
  `Get-AuthenticodeSignature` muss `Valid` melden, und der Aussteller
  (`SignerCertificate.Subject`) muss der erwartete sein, fest im Code
  hinterlegt. Ab der ersten signierten Fassung wird ein unsigniertes oder
  fremd signiertes Setup **nie** gestartet, auch nicht nach Rückfrage.
  Bis dahin: Selbst-Update nur mit Prüfsumme und dem Hinweis, dass die
  Fassung noch unsigniert ist, oder das Selbst-Update erst mit der Signatur
  freischalten. **Empfehlung: erst mit Signatur freischalten.**
- **Keine Rechteausweitung durch die Hintertür**: Die Oberfläche läuft ohnehin
  erhöht. Das Setup wird aus `%TEMP%` des Benutzers gestartet; zwischen Prüfen
  und Starten darf niemand die Datei tauschen können. Deshalb die Datei nach
  dem Download mit exklusivem Zugriff öffnen, prüfen und aus demselben
  Handle-Zeitfenster starten, oder in einen nur für Administratoren
  beschreibbaren Ordner (`%ProgramData%\UpdateManager\setup\`) laden.
- **Rückweg**: Scheitert das Setup, bleibt die alte Fassung stehen (Inno Setup
  ersetzt erst am Ende). Das Protokoll bekommt den Exit-Code.

## Was noch fehlt

- Signierung über SignPath (Antrag, Einrichtung im Release-Workflow, dort als
  auskommentierter Schritt vorbereitet). Danach `$SU_SignaturAussteller` setzen
  und `selbstUpdate.installieren` in der Vorgabe auf `true`.
- Ein erstes echtes Release (öffentliches Repo legt David an), damit der Weg
  einmal von Anfang bis Ende auf einem Rechner läuft. Bis dahin ist Installieren
  nur gegen eine Attrappe geprobt.
- Offen: Im Windows-Setup läuft die `.bat` des Fensters noch, während sie ersetzt
  wird; auf einem echten Release prüfen, dass das Setup sie überschreiben darf.
