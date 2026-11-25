' Universal Update Manager - starter without any console flash
' SPDX-License-Identifier: GPL-3.0-or-later
' Copyright (C) 2025-2026 MelucioLabs / David Vaupel
' https://github.com/MelucioLabs/update-manager
'
' WHY THIS FILE EXISTS (Chip 53, 25.11.2026 - starter trick, nutzi A / David:
' keep the proven trick, do not invent a new one)
'
' Every start that goes THROUGH a .bat owns a cmd window, even when it is
' minimized or short-lived: cmd.exe allocates a console the moment it runs,
' so something always blinks before the WPF window shows. wscript.exe runs a
' .vbs WITHOUT ever allocating a console, which makes it the proven
' flash-free starter on Windows.
'
' This starter therefore asks UAC DIRECTLY for the hidden PowerShell that
' carries the window - the same field-verified -Command with & { ... } form
' the .bat uses since Chip 52 (elevated + hidden + a file argument died with exit code
' -196608, never start that way again). Sessions that are already elevated
' start without a second UAC question.
'
' WHAT IT IS NOT
' No replacement of the logic. The .bat stays for everyone who starts from a
' console on purpose; its behavior and the probe (section 5g) are unchanged.
' This starter only changes WHERE the start comes from: the installer
' shortcuts point here, not at the .bat.
'
' FAILURES STAY VISIBLE (Leiti, 25.11.2026): a declined UAC prompt or a
' never-starting carrier cannot always be caught as an error here -
' ShellExecute may simply return with nothing started. So after asking, the
' starter looks (WMI, up to five seconds) for the elevated PowerShell that
' carries the GUI; none showing up means declined or dead: log line plus
' wscript MessageBox, the same channel the .bat uses. While the UAC question
' itself stands open, the user is still deciding and the wait restarts -
' with a hard stop so this starter can never outlive the session. On a
' workshop machine a parallel -NurPruefen launch can satisfy that check; on
' a user desktop nothing else names this file.
' Encoding: this file must stay ANSI (Windows-1252), wscript does not read
' UTF-8 - the German message texts carry the umlauts as single bytes.
Option Explicit

Dim fso, wsShell, ordner, guiPfad, logPfad

Set fso = CreateObject("Scripting.FileSystemObject")
Set wsShell = CreateObject("WScript.Shell")

' The starter carries whatever folder it sits in - the installer copies it
' next to the GUI into {app}, a workshop copy works straight from the repo.
ordner = fso.GetParentFolderName(WScript.ScriptFullName)
guiPfad = fso.BuildPath(ordner, "update-manager-gui.ps1")
logPfad = fso.BuildPath(wsShell.ExpandEnvironmentStrings("%ProgramData%"), _
    "UpdateManager\universal-update-manager.log")

Sub Misslinge(nachricht)
    ' Same failure channel as the .bat: log line first, visible message
    ' second (here a wscript MessageBox, because no console exists).
    On Error Resume Next
    Dim strom
    Set strom = fso.OpenTextFile(logPfad, 8, True)
    strom.WriteLine "[" & FormatDateTime(Now, vbGeneralDate) & "] [START] [ERROR] " & nachricht
    strom.Close
    MsgBox nachricht & vbCrLf & vbCrLf & "Protokoll: " & logPfad, _
        vbExclamation, "Universal Update Manager"
    WScript.Quit 1
End Sub

If Not fso.FileExists(guiPfad) Then
    Misslinge "Die Datei update-manager-gui.ps1 fehlt neben dem Starter."
End If

Dim shellAnwendung
On Error Resume Next
Set shellAnwendung = CreateObject("Shell.Application")
If Err.Number <> 0 Then
    Misslinge "Die Shell-Erhöhung ist nicht verfügbar: " & Err.Description
End If

Dim argumente
argumente = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & _
    """& { Set-Location -LiteralPath '" & ordner & "'; & '" & guiPfad & "' }"""

Dim beschreibung
Err.Clear
shellAnwendung.ShellExecute "powershell.exe", argumente, ordner, "runas", 0
If Err.Number <> 0 Then
    beschreibung = Err.Description
    Err.Clear
    Misslinge "Die Administrator-Rechte wurden verweigert oder der Start schlug fehl (" & beschreibung & ")."
End If
On Error GoTo 0

Dim wmi, abfrage, treffer, uhr, harteGrenze
Set wmi = GetObject("winmgmts:root\cimv2")
uhr = Timer
harteGrenze = uhr + 120
Do
    WScript.Sleep 500
    If wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='consent.exe'").Count > 0 Then
        uhr = Timer
        harteGrenze = uhr + 120
    End If
    Set abfrage = wmi.ExecQuery( _
        "SELECT ProcessId FROM Win32_Process WHERE CommandLine LIKE '%update-manager-gui.ps1%'")
    treffer = abfrage.Count
    If treffer > 0 Then Exit Do
Loop While Timer < uhr + 5 And Timer < harteGrenze

If treffer = 0 Then
    Misslinge "Die Administrator-Rechte wurden verweigert oder der Start schlug fehl."
End If
