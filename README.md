# Universal Update Manager

**[Deutsche Version](README_DE.md)** | English Version

---

**Platform:** Windows 10/11
**Language:** PowerShell

> This project was developed with AI assistance (Claude) and also serves as a learning project for better understanding PowerShell automation.

---

## Description

A comprehensive Windows update manager that consolidates updates from multiple sources into a single tool with hardware auto-detection, flexible configuration, silent background mode, and Windows Task Scheduler integration.

---

## Features

### Multi-Source Update Management:
- **Windows Update** - Official Microsoft updates (including optional driver updates)
- **Winget** - Microsoft package manager
- **Chocolatey** - Community package manager
- **Microsoft Store** - UWP app updates (opens Store for manual confirmation)

### Hardware Auto-Detection:
- **CPU Vendor** - Intel, AMD
- **GPU Vendor** - NVIDIA (App + GeForce Experience fallback), AMD, Intel
- **Mainboard** - MSI Center support
- **Automatic Driver Selection** - Updates only relevant hardware vendors

### Silent Mode:
- Runs Winget + Chocolatey fully in the background (no interactive prompts)
- **Pinned packages** (marked by Winget as requiring "explicit targeting") are automatically updated individually via `--id`
- **Internet retry:** Waits up to 2.5 minutes for an internet connection after boot (5 attempts, 30s apart)
- **Lock file protection:** Prevents parallel silent mode runs when multiple task triggers fire
- Skips if already ran today (duplicate-run protection)
- Detailed logging: Shows which packages were actually updated (name + count)
- Can be triggered via `-SilentMode` parameter

### Automatic Scheduling (Task Scheduler):
- Creates a Windows Task Scheduler entry for fully automated silent updates
- **Dual-trigger:** runs daily at a set time AND 2 minutes after every login
- Login trigger catches missed runs (e.g. PC was off during scheduled time)
- Skips if already ran today to prevent duplicate execution
- Detect, edit, and delete existing tasks directly from the menu

### Multilingual:
- **Automatic language detection** based on Windows system locale
- German (`de`) and English (all other locales) supported
- No manual language selection needed

### Configuration:
- **JSON-based** - Easy to customize (`update-config.json`)
- **Flexible** - Enable/disable components individually
- **KISS Principle** - Only settings that are actually used

---

## Open Source and installation

The Update Manager is **open source under the GPL-3.0** (see below). The
public repository is `github.com/MelucioLabs/update-manager`; it is a mirror
of this folder, the source of truth stays in the MelucioLabs monorepo.

**The goal, for people who do not want to touch a console:**

1. Download the setup once from `meluciolabs.de/update`.
2. Run it. It installs to `C:\Program Files\MelucioLabs Update-Manager`,
   adds a Start menu entry, optionally a desktop shortcut, and on request
   the nightly background check (Task Scheduler).
3. From then on the manager updates itself from the GitHub releases.

**Status:** The installer script (`installer/update-manager.iss`) and the
release workflow are prepared. **Signed setups are not available yet**; code
signing through the SignPath Foundation is planned. Until then Windows
SmartScreen will warn about an unknown publisher. The self-update is a
concept (`SELBST-UPDATE.md`), not yet built. Linux and macOS have their own
script in `linux/` (see `linux/LIESMICH.md`).

Own settings belong in `update-config.local.json` next to the scripts; the
setup never touches that file, so it survives every update.

---

## Code signing policy

Setups are meant to be signed with a certificate from the SignPath
Foundation. **Status: application in preparation, nothing granted yet**; until then every
setup is unsigned. Roles, release process, privacy and the exact wording
that applies from the first signed release are in
[`CODE-SIGNING-POLICY.md`](CODE-SIGNING-POLICY.md).

---

## Installation & Usage

### Requirements:
- Windows 10/11
- PowerShell 5.1 or higher
- Administrator rights
- PSWindowsUpdate module (installed automatically if missing)

### Quick Start:
1. Download all files to a folder
2. Double-click `universal-update-manager.bat`
3. Confirm admin elevation
4. Select option from menu

### Manual Execution:
```powershell
# Run as Administrator
.\universal-update-manager.ps1

# Run in Silent Mode directly (e.g. from Task Scheduler)
.\universal-update-manager.ps1 -SilentMode
```

---

## Menu Overview

| # | Option | Description |
|---|--------|-------------|
| 1 | Full Update | All sources + hardware vendors |
| 2 | Winget only | Winget package updates |
| 3 | Chocolatey only | Chocolatey package updates |
| 4 | Windows Update only | Microsoft updates + drivers |
| 5 | Microsoft Store | Opens Store for UWP updates |
| 6 | Hardware Vendors | NVIDIA / AMD / Intel / MSI tools |
| 7 | Silent Mode | Background update (Winget + Choco) |
| 8 | Auto-Update Setup | Create/edit/delete Task Scheduler entry |
| 9 | System Info | Hardware & installed tool overview |
| L | View Log | Last 50 lines of the log file |

> Most inputs use single-key press (no Enter required). Only the time input for Task Scheduler needs Enter.

---

## Configuration

### update-config.json Structure:

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

### Enable/Disable Components:
- Set `enabled` to `true` or `false`
- Configuration persists across runs

---

## Driver Updates

| Vendor | Tool | Notes |
|--------|------|-------|
| **NVIDIA** | NVIDIA App (priority) or GeForce Experience | Auto-detected |
| **AMD** | Radeon Software | Auto-detected |
| **Intel** | Intel Driver & Support Assistant | Auto-detected |
| **MSI** | MSI Center | Mainboard auto-detected |

---

## Task Scheduler Details

The auto-update setup (Menu item 8) creates a scheduled task with two triggers:

- **Daily trigger** – runs at the time you specify
- **AtLogOn trigger** – runs 2 minutes after every login

The login trigger ensures missed runs are caught after the PC was off.
A log-based check prevents the task from running more than once per day.

The task runs under your user account with highest privileges and does **not** require a password prompt.


**The time can also be set in the window** (since 22 Sep 2026): at the bottom of
the "what should be checked" block there is "Naechtlich um HH:MM / Uebernehmen",
plus a line with the next and last run. No detour through the console menu. The
window computes nothing itself - it asks the core (`-AufgabeStatus`) and lets it
register the task (`-AufgabeZeit HH:MM`).

**The task points at the file it was registered from.** If the folder is later moved or copied, the scheduler keeps starting the old file — and then the nightly run uses a different version than the manual one. That was exactly the case between 21 and 22 Sep 2026 (466 lines apart, the nightly run being the older one). The manager therefore checks this on every start and reports a mismatch in log and console; it **changes nothing** — re-pointing a task is a decision. To fix: run menu entry 8 from the file that should run from now on.

---

## Local settings and notifications

Two files side by side: `update-config.json` belongs to the tool and lives in
the repo, `update-config.local.json` belongs to the **machine** and is not
versioned. The local one wins section by section, so a local setting survives
the next `git pull` and the tool can be handed on without cleaning up first.

A notification is sent when a **nightly** run had errors, and only then:

```json
{
  "benachrichtigung": {
    "enabled": true,
    "url": "https://ntfy.example.org/<topic>",
    "authDatei": "%USERPROFILE%\.ntfy-auth"
  }
}
```

The credentials file holds a single line `user:password` and does not belong in
the repo. If it or the address is missing, the manager says so in the log
instead of silently doing nothing.

---

## Probe (a test without side effects)

```
pwsh -File probe.ps1
```

Checks in seconds and without administrator rights: syntax of both scripts, the
BOM (without it Windows PowerShell 5.1 mangles the umlauts), whether every job
name used by the window exists in the core, whether every text key is present in
both language tables, whether the window builds in light **and** dark, and
whether the configuration is readable.

The window itself offers `-NurPruefen` (builds, opens nothing) and
`-Abbild <file.png>` (renders the window to a file without opening it).

---

## Light and dark

The window follows the Windows **app mode** setting; `-Erscheinung hell` or
`-Erscheinung dunkel` overrides it. The colours are measured, not guessed: body
text reaches at least 4.5:1 in both variants. White on the brand purple #7C6AF5
only reaches 4.01:1, so filled buttons use #5B47D6 (6.33:1) while the brand
purple stays for surfaces and borders.

---

## Log Files

Logs are stored in:
```
C:\ProgramData\UpdateManager\universal-update-manager.log
```

> This path is accessible to all user accounts, including the scheduled task context.

The log keeps **7 days** (since 3 Oct 2026). On every start, older lines are
dropped; leftover files next to it (`.ansi-sicherung`, `.log.1`, dated archives)
go after the same period. Before that, two size-based rotations ran side by
side (1 MB and 5 MB), and neither said how far back the log reaches.

A silent run ends with `[SILENT-DONE]`, a failed one with `[SILENT-FAILED]`.
Only the first counts as "already ran today"; a failed run is retried by the
task's next trigger.

**What the nightly run did is shown in the window** since 22 Sep 2026 - one line
below the hardware ("Letzter stiller Lauf: ... - 3 Updates"), including the error
count if there was one. A run without a window is otherwise invisible.

---

## File Structure

```
update-manager/
├── universal-update-manager.bat    # Launcher (admin elevation), console menu
├── universal-update-manager.ps1    # Main script
├── update-manager-gui.bat          # Launcher for the window (admin elevation)
├── update-manager-gui.ps1          # Window (WPF)
├── update-config.json              # Default configuration
├── update-config.local.json        # Own settings (not shipped, survives updates)
├── probe.ps1                       # Test without side effects
├── diagnose-silent.ps1             # Diagnosis for the silent mode
├── installer/update-manager.iss    # Inno Setup script
├── linux/update-manager.sh         # Linux and macOS
├── .github/workflows/release.yml   # Build (active in the public repo)
├── LICENSE                         # GPL-3.0
├── NOTICE                          # Copyright, license, trademark
├── README.md                       # English documentation
└── README_DE.md                    # German documentation
```

---

## Changelog

### v3.1 (2026-02-26)
- **Silent Mode fix:** Winget updates now install reliably (including via Task Scheduler)
- **Pinned packages:** Automatically updated individually via `winget upgrade --id`
- **Internet retry:** Waits up to 2.5 min for internet connection after boot
- **Lock file:** Prevents parallel silent mode runs from dual-trigger
- **Single-key input:** Menu and yes/no prompts work without pressing Enter
- **Detailed logging:** Shows which packages were actually updated
- Winget output parser improved for German and English locales

### v3.0 (2026-02-24)
- Silent Mode added (Winget + Chocolatey in background, no prompts)
- Task Scheduler integration with dual-trigger (Daily + AtLogOn with 2min delay)
- Duplicate-run protection: skips if already ran today
- Automatic DE/EN language detection based on system locale
- Log path moved to `C:\ProgramData\UpdateManager` (multi-account compatible)
- Winget `--include-unknown` removed (safer for production use)
- Winget Silent Mode timeout increased to 300s
- Menu restructured to 10 items
- Task Scheduler status/edit/delete integrated in menu item 8
- UTF-8 with BOM for correct special character display in PowerShell 5.1
- Internet connection check improved (TCP-based, faster)

### v2.2 (2025-11-23)
- Added NVIDIA App support (replaces GeForce Experience)
- Hardware vendor `enabled` flags now respected
- Cleaned up config (KISS principle)
- Log path moved to `%LOCALAPPDATA%\UpdateManager`
- Simplified prerequisites check

### v2.1 (2025-11-02)
- Config settings now actually used
- PSWindowsUpdate module check at startup
- Special character fixes
- Improved error handling

---

## Author

**David Vaupel**
Windows Automation Enthusiast | PowerShell Learner

---

## License

Copyright (C) 2025-2026 MelucioLabs / David Vaupel

This program is free software: you can redistribute it and/or modify it under
the terms of the **GNU General Public License, version 3 or (at your option)
any later version** (`SPDX-License-Identifier: GPL-3.0-or-later`). It is
distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY. The
full text is in [`LICENSE`](LICENSE).

In short: use it, change it, pass it on. Whoever passes on a modified version
has to publish its source under the same license.

### Name and trademark

The license covers the source code. The name and the mark "MelucioLabs" (including
logos and brand colors) are not part of the free license. Modified versions
may be passed on under the license, but not under this name or mark in a way
that suggests they come from MelucioLabs.

---

**Status:** Production-Ready
**Last Updated:** February 2026
