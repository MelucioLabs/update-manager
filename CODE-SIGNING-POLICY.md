<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Code signing policy

> **Status / Stand:** Application in preparation, nothing granted yet. Until SignPath Foundation
> has accepted the project, all setups are **unsigned** and Windows SmartScreen
> shows a warning. / Antrag in Vorbereitung, nichts erteilt. Bis die SignPath Foundation
> das Projekt aufgenommen hat, sind alle Setups **unsigniert**; Windows
> SmartScreen warnt dann.
>
> *Maintainer: on acceptance, replace this block by the sentence in the next
> section and update README, `meluciolabs.de/update` and the release notes
> (steps in the monorepo: `docs/update-manager-signpath-antrag.md`).*

## English

Free code signing provided by [SignPath.io](https://about.signpath.io/),
certificate by [SignPath Foundation](https://signpath.org/).

*(This sentence applies from the first signed release on.)*

**What is signed.** Only the Windows setup
`MelucioLabs-Update-Manager-Setup-<version>.exe`, built from this repository
by the GitHub Actions workflow [`release.yml`](.github/workflows/release.yml)
on GitHub-hosted runners. Nothing else is signed, no third-party binaries.
The PowerShell scripts in the setup are plain text and part of the repository.

**Team roles.** The project is maintained by one person, who holds all roles.

- Authors (may change the code without review): [Owners of the MelucioLabs organization](https://github.com/orgs/MelucioLabs/people?query=role%3Aowner)
- Reviewers (review every change from non-members, e.g. pull requests): same team
- Approvers (approve each signing request, i.e. each release, by hand in SignPath): same team

All team members use multi-factor authentication for GitHub and for SignPath.
If more people join, they are listed here with their role before they get
access.

**Release process.** A release starts with a version tag (`v3.2.0`). The
workflow checks that the tag matches the version in the scripts, runs the
test probe, builds the setup and submits it to SignPath. **Every release needs
manual approval in SignPath** before it is signed. The workflow then checks
the signature (valid, issued to SignPath Foundation) and publishes the signed
setup together with a SHA-256 checksum.

**Privacy policy.** The Update Manager has no telemetry and no account. It
connects to other systems only for these purposes, all of them part of what
the user asks it to do or of its documented behavior:

- The package sources the user updates from: winget, Chocolatey,
  Windows Update, Microsoft Store, and the PowerShell module `PSWindowsUpdate`
  from the PowerShell Gallery (installed on first use). Their privacy
  policies apply.
- Once a day, the window asks `api.github.com` (this repository only) whether
  a newer release exists, for the sole purpose of notifying about updates. The
  provider (MelucioLabs, contact: see the imprint of meluciolabs.de) receives
  no data. GitHub (Microsoft, USA) sees the usual request data (IP
  address, `User-Agent`) and is responsible for that itself; GitHub's
  [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
  applies. Switch it off with `selbstUpdate.pruefen = false` in
  `update-config.local.json`. Downloading and installing a new version is off
  by default.
- A notification to an ntfy server, only if the user enters one in the
  configuration (off by default).

The program does not transfer any other information to other networked
systems.

**System changes.** The Update Manager installs and updates software on the
user's request and runs with administrator rights. The setup asks before it
creates the optional scheduled task (daily 04:00 and after logon) and removes
it on uninstall. The module `PSWindowsUpdate` is installed for the current user
on first use of the Windows Update function. Uninstall: Windows "Apps &
features" or the Start menu entry; the user's own settings file
`update-config.local.json` stays.

**No hacking tools.** The software does not scan for or exploit security
vulnerabilities and does not circumvent security measures.

**Reporting a violation:** [issues](https://github.com/MelucioLabs/update-manager/issues)
or support@signpath.io (see the
[SignPath Foundation conditions](https://signpath.org/terms)).

## Deutsch

Kostenlose Code-Signatur durch [SignPath.io](https://about.signpath.io/),
Zertifikat der [SignPath Foundation](https://signpath.org/). *(Gilt ab dem
ersten signierten Release.)*

**Was signiert wird.** Nur das Windows-Setup
`MelucioLabs-Update-Manager-Setup-<Version>.exe`, gebaut aus diesem Repository
vom GitHub-Actions-Workflow [`release.yml`](.github/workflows/release.yml) auf
GitHub-gehosteten Runnern. Sonst nichts, keine fremden Programmdateien. Die
PowerShell-Skripte im Setup sind Klartext und Teil des Repositorys.

**Rollen.** Das Projekt pflegt eine Person, die alle Rollen trägt: Autor
(ändert den Code ohne Prüfung), Prüfer (prüft Änderungen von Nicht-Mitgliedern,
etwa Pull Requests) und Freigeber (gibt jede Signieranfrage, also jedes
Release, in SignPath von Hand frei). Siehe die Links oben. Alle nutzen
Mehr-Faktor-Anmeldung für GitHub und SignPath. Kommen weitere Personen hinzu,
stehen sie hier mit ihrer Rolle, bevor sie Zugriff bekommen.

**Ablauf eines Releases.** Ein Versions-Tag (`v3.2.0`) startet den Workflow:
Tag gegen Skript-Version abgleichen, Bausteinprobe, Setup bauen, an SignPath
senden. **Jedes Release braucht eine Freigabe von Hand in SignPath.** Danach
prüft der Workflow die Signatur (gültig, Aussteller SignPath Foundation) und
veröffentlicht das signierte Setup samt SHA-256-Prüfsumme.

**Datenschutz.** Keine Telemetrie, kein Konto. Verbindungen gibt es nur zu den
Paketquellen, aus denen der Nutzer aktualisiert (winget, Chocolatey, Windows
Update, Microsoft Store, PowerShell-Katalog für `PSWindowsUpdate`), einmal am
Tag zu `api.github.com` mit der Frage nach einer neueren Fassung (nur zur Benachrichtigung, der Anbieter erhält keine Daten, GitHub in den USA ist selbst verantwortlich; abschaltbar
mit `selbstUpdate.pruefen = false`; Herunterladen und Installieren sind aus der
Voreinstellung heraus aus) und, nur bei eigener Eintragung, zu einem ntfy-Server.
Darüber hinaus überträgt das Programm nichts an andere vernetzte Systeme.

**Änderungen am System.** Das Programm installiert und aktualisiert Software auf
Wunsch und läuft mit Administratorrechten. Die optionale Aufgabe (täglich
04:00, nach der Anmeldung) legt das Setup nur nach Rückfrage an und entfernt
sie bei der Deinstallation; die eigene `update-config.local.json` bleibt
erhalten. Das Modul `PSWindowsUpdate` kommt beim ersten Gebrauch der
Windows-Update-Funktion für den aktuellen Benutzer dazu.

**Keine Hacking-Werkzeuge.** Das Programm sucht keine Sicherheitslücken und
umgeht keine Schutzmaßnahmen.
