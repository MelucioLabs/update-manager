# Selbst-Update (Konzept, noch nicht gebaut)

Stand 28.09.2026. **Entwurf.** Im Code gibt es dafür bisher nur die Konstante
`$UpdaterVersion` in `universal-update-manager.ps1` und `update-manager-gui.ps1`
(beide gleich, der Release-Workflow prüft das). Netzwerkcode steht absichtlich
noch nicht in der Oberfläche: Er wäre ungetestet, und ein Updater, der sich
selbst kaputt aktualisiert, ist schlimmer als keiner.

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

## Was dafür noch fehlt

- Signierung über SignPath (Antrag, Einrichtung im Release-Workflow, dort als
  auskommentierter Schritt vorbereitet).
- Der Code in `update-manager-gui.ps1`: Abfrage, Vergleich, Zeile im Kopf,
  Download, Prüfung, Start. Geschätzt 150 bis 200 Zeilen, dazu eine Probe in
  `probe.ps1` für den Versionsvergleich und die Adressprüfung (ohne Netz, gegen
  eine gespeicherte API-Antwort).
- Ein erstes echtes Release, gegen das getestet werden kann.
