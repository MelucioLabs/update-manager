; SPDX-License-Identifier: GPL-3.0-or-later
; Copyright (C) 2025-2026 MelucioLabs / David Vaupel
;
; Inno-Setup-Skript fuer den MelucioLabs Update-Manager (Windows).
;
; Bauen (Inno Setup 6.3 oder neuer):
;   iscc /DAppVersion=3.2.0 installer\update-manager.iss
; Der Release-Workflow (.github/workflows/release.yml) setzt die Version aus
; dem Git-Tag und prueft vorher, dass sie zu $UpdaterVersion in beiden
; Skripten passt. Ergebnis landet in dist\.
;
; UNGETESTET: geschrieben ohne Windows-Rechner. Vor dem ersten Release einmal
; von Hand bauen, installieren, Aufgabe pruefen, deinstallieren.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName       "MelucioLabs Update-Manager"
#define AppPublisher  "MelucioLabs"
#define AppRepo       "https://github.com/MelucioLabs/update-manager"
; Name der geplanten Aufgabe, wie in universal-update-manager.ps1 ($AufgabeName).
#define AufgabeName   "UpdateManager-SilentMode"
; Kurzlebige Aufgabe fuer den Nachlauf der Benutzer-Pakete (Update-BenutzerPakete).
#define NachlaufName  "UpdateManager-Benutzerpakete"
#define PsExe         "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
; Die AppId NIE aendern: an ihr erkennt Windows ein Update derselben
; Installation. Eine neue Id waere eine zweite Installation daneben.
AppId={{6F0B8C0E-5B7A-4B8B-9E61-3C2B7A1D5E42}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://meluciolabs.de
AppSupportURL={#AppRepo}/issues
AppUpdatesURL={#AppRepo}/releases
DefaultDirName={autopf}\MelucioLabs Update-Manager
DefaultGroupName=MelucioLabs Update-Manager
DisableProgramGroupPage=yes
; Admin: Installation nach Programme, Aufgabe mit hoechsten Rechten.
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=MelucioLabs-Update-Manager-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Sprache nach Windows-Anzeigesprache, der Dialog nur, wenn sie nicht passt.
ShowLanguageDialog=auto
UninstallDisplayName={#AppName}
UninstallDisplayIcon={#PsExe}
SetupLogging=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
de.GruppeHintergrund=Hintergrund:
en.GruppeHintergrund=Background:
de.TaskHintergrund=Automatisch im Hintergrund prüfen (täglich 04:00 und nach der Anmeldung)
en.TaskHintergrund=Check automatically in the background (daily at 04:00 and after logon)
de.AufgabeWirdEingerichtet=Aufgabenplanung wird eingerichtet …
en.AufgabeWirdEingerichtet=Setting up the scheduled task …
de.StartGui=Update-Manager jetzt öffnen
en.StartGui=Open the Update Manager now
de.KonsoleName=Update-Manager (Konsole)
en.KonsoleName=Update Manager (console)
de.GuiKommentar=Updates für Programme, Windows und Treiber prüfen und installieren
en.GuiKommentar=Check and install updates for programs, Windows and drivers

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "hintergrund"; Description: "{cm:TaskHintergrund}"; GroupDescription: "{cm:GruppeHintergrund}"; Flags: unchecked

[Files]
; update-config.json ist die VORGABE und wird bei jedem Update ersetzt.
; update-config.local.json (eigene Einstellungen) steht absichtlich NICHT
; hier: Was Setup nicht installiert, fasst es weder beim Update noch bei der
; Deinstallation an. Damit uebersteht die Datei jedes Update.
Source: "..\universal-update-manager.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\update-manager-gui.ps1";       DestDir: "{app}"; Flags: ignoreversion
Source: "..\selbst-update.ps1";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\protokoll-ansicht.ps1";       DestDir: "{app}"; Flags: ignoreversion
Source: "..\universal-update-manager.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\update-manager-gui.bat";       DestDir: "{app}"; Flags: ignoreversion
Source: "..\update-config.json";           DestDir: "{app}"; Flags: ignoreversion
Source: "..\probe.ps1";                    DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE";                      DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md";                    DestDir: "{app}"; Flags: ignoreversion
Source: "..\README_DE.md";                 DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Die Verknuepfung zeigt auf die .bat und NICHT direkt auf powershell.exe:
; Die Oberflaeche braucht Administratorrechte und fordert sie nicht selbst an
; (sie meldet nur, dass sie fehlen). Die .bat holt die Erhoehung per UAC und
; startet dann powershell -WindowStyle Hidden. runminimized haelt das kurze
; Konsolenfenster vor der UAC-Abfrage klein.
Name: "{group}\{#AppName}"; Filename: "{app}\update-manager-gui.bat"; WorkingDir: "{app}"; IconFilename: "{#PsExe}"; Comment: "{cm:GuiKommentar}"; Flags: runminimized
Name: "{group}\{cm:KonsoleName}"; Filename: "{app}\universal-update-manager.bat"; WorkingDir: "{app}"; IconFilename: "{#PsExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\update-manager-gui.bat"; WorkingDir: "{app}"; IconFilename: "{#PsExe}"; Comment: "{cm:GuiKommentar}"; Flags: runminimized; Tasks: desktopicon

[Run]
; Hintergrund-Pruefung ueber den vorhandenen Parameter -AufgabeZeit HH:MM
; (Register-UpdateTask im Kern: taeglich zur Uhrzeit plus bei der Anmeldung,
; hoechste Rechte, eingetragen wird der Pfad dieser Installation).
; Nur, wenn es die Aufgabe noch NICHT gibt: Sonst wuerde ein stilles Update
; (Setup merkt sich die Haekchen) eine im Fenster geaenderte Uhrzeit jedes
; Mal auf 04:00 zuruecksetzen.
; Grenze: Die Aufgabe laeuft unter dem Konto, das Setup erhoeht ausfuehrt.
; Startet ein Standardnutzer Setup mit fremden Admin-Zugangsdaten, landet
; sie beim Admin-Konto. Dann im Fenster unter dem eigenen Konto neu setzen.
Filename: "{#PsExe}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\universal-update-manager.ps1"" -AufgabeZeit 04:00"; StatusMsg: "{cm:AufgabeWirdEingerichtet}"; Tasks: hintergrund; Check: AufgabeFehlt; Flags: runhidden waituntilterminated

; Nach der Installation oeffnen. postinstall startet als urspruenglicher
; (nicht erhoehter) Nutzer; die .bat fragt dann selbst per UAC.
Filename: "{app}\update-manager-gui.bat"; Description: "{cm:StartGui}"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent shellexec runminimized

[UninstallRun]
; Die geplante Aufgabe gehoert zur Installation und geht mit ihr.
; schtasks meldet einen Fehler, wenn es sie nicht gibt; Setup ignoriert den
; Exit-Code hier, die Deinstallation laeuft weiter.
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""{#AufgabeName}"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "AufgabeEntfernen"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""{#NachlaufName}"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "NachlaufEntfernen"

[Code]
{ True, wenn die geplante Aufgabe noch nicht existiert. schtasks /Query
  liefert 0, wenn es sie gibt. }
function AufgabeFehlt: Boolean;
var
  Code: Integer;
begin
  if Exec(ExpandConstant('{sys}\schtasks.exe'), '/Query /TN "{#AufgabeName}"', '',
          SW_HIDE, ewWaitUntilTerminated, Code) then
    Result := (Code <> 0)
  else
    Result := True;
end;
