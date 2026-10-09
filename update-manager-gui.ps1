# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025-2026 MelucioLabs / David Vaupel
# https://github.com/MelucioLabs/update-manager

<#
    Universal Update Manager — Fenster statt Konsole.

    WOFUER (David, 21.09.2026)
    Der Manager kann viel, sah aber aus wie ein Terminal, und genau das ist
    der Punkt, an dem man ihn niemandem weitergeben moechte. Hier liegt
    dieselbe Arbeit hinter einem Fenster: umlegen, einmal druecken, zusehen.

    WAS ER NICHT IST
    Keine zweite Fassung der Logik. Jede Aufgabe startet
    `universal-update-manager.ps1 -Auftrag <name>` als eigenen Prozess und
    zeigt dessen Ausgabe mit. Eine Oberflaeche, die die Update-Schritte selbst
    noch einmal beschreibt, laeuft vom Kern weg — beim Update-Manager ist
    genau das am 20.09.2026 passiert, als zwei Fassungen nebeneinander lagen.

    WARUM EIN EIGENER PROZESS UND KEIN RUNSPACE
    Weil die Update-Funktionen Write-Host benutzen und externe Programme
    aufrufen. Deren Ausgabe faengt man aus einem Kindprozess zuverlaessig ab;
    Write-Host in einen Runspace umzubiegen ist eine Bastelei, die bei jedem
    zweiten Werkzeug bricht.

    ZWEI DINGE, DIE BEIM ERSTEN ANLAUF FALSCH WAREN (21.09.2026, Davids Bild)

    1. DIESE DATEI BRAUCHT EIN BOM. Ohne Byte Order Mark liest Windows
       PowerShell 5.1 eine .ps1 als Windows-1252, und aus "geprüft" wird
       "geprÃ¼ft". Die .bat startet `powershell`, also 5.1 — verlassen kann
       man sich hier nur auf das BOM. Wer die Datei mit einem Werkzeug
       bearbeitet, das BOM-los speichert, bringt den Fehler zurueck.

    2. UMSCHALTER, KEINE HAEKCHEN. Hausregel seit dem 14.08.2026: groessere
       Trefferflaeche, der Zustand ist auf einen Blick da, und es liest sich
       wie eine Entscheidung statt wie Kleingedrucktes.
#>

param(
    # Fuer den Blindtest in der Werkstatt: baut das Fenster auf, prueft, dass
    # alle benannten Elemente da sind, und beendet sich. Oeffnet nichts.
    [switch]$NurPruefen,

    # Hell oder dunkel von Hand. Vorgabe ist 'system': Dann entscheidet die
    # Windows-Einstellung. Die beiden anderen Werte sind fuer den Blindtest da
    # (beide Paletten pruefen, ohne an der Systemeinstellung zu drehen) und
    # fuer den Fall, dass jemand es dauerhaft anders will.
    [ValidateSet('system','hell','dunkel')]
    [string]$Erscheinung = 'system',

    # Legt ein Bild des Fensters ab, ohne es zu oeffnen. Dafuer da, dass man
    # eine Aenderung am Aussehen ansehen kann, ohne den Manager zu starten —
    # und dass sich hell und dunkel nebeneinanderlegen lassen.
    [string]$Abbild,

    # Wie -NurPruefen, aber es wartet auf das Nachladen: Hardware und
    # Aufgabenplanung werden nebenher geholt, und dieser Lauf prueft, dass sie
    # wirklich im Fenster ANKOMMEN. Ohne das waere der einzige automatische
    # Test blind fuer genau den Teil, der zuletzt umgebaut wurde. Oeffnet
    # nichts: Das Fenster bleibt ungezeigt, die Nachrichtenschleife wird von
    # Hand gedreht.
    [switch]$Selbsttest
)

# ============================================
# VERSION
# ============================================
# Dieselbe Zahl steht in universal-update-manager.ps1. Der Release-Workflow
# (.github/workflows/release.yml) bricht ab, wenn der Tag v<Version> nicht zu
# BEIDEN Konstanten passt; das Setup bekommt sie von dort. Grundlage fuer das
# spaetere Selbst-Update (SELBST-UPDATE.md).
$UpdaterVersion = '3.2.0'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$SkriptOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
$Kern         = Join-Path $SkriptOrdner 'universal-update-manager.ps1'
# Dieselbe PowerShell, die dieses Fenster traegt, startet auch den Kern.
# (In der Arbeits-Sitzung heisst dieselbe Angabe `$Exe`; hier braucht es sie
# auch ausserhalb, fuer die kurzen Abfragen zwischendurch.)
$ExePfad      = (Get-Process -Id $PID).Path
$LogPfad      = Join-Path $env:ProgramData 'UpdateManager\universal-update-manager.log'

# Selbst-Update (SELBST-UPDATE.md): eigene Datei, nur Funktionen. Fehlt sie
# oder laesst sie sich nicht laden, bleibt das Fenster ohne diese Zeile, es
# geht nichts anderes kaputt.
$SelbstUpdateDatei   = Join-Path $SkriptOrdner 'selbst-update.ps1'
$SelbstUpdateZustand = Join-Path $env:ProgramData 'UpdateManager\selbst-update.json'
$SelbstUpdateOrdner  = Join-Path $env:ProgramData 'UpdateManager\setup'
# Protokoll-Ansicht (protokoll-ansicht.ps1): reine Funktionen. Fehlt die Datei,
# bleibt die Karte bei "Wird gelesen" und das Protokoll oeffnet wie frueher.
$AnsichtDatei   = Join-Path $SkriptOrdner 'protokoll-ansicht.ps1'
$AnsichtGeladen = $false
if (Test-Path $AnsichtDatei) {
    try { . $AnsichtDatei; $AnsichtGeladen = $true } catch { }
}
$SelbstUpdateGeladen = $false
if (Test-Path $SelbstUpdateDatei) {
    try { . $SelbstUpdateDatei; $SelbstUpdateGeladen = $true } catch { }
}

if (-not (Test-Path $Kern)) {
    [System.Windows.MessageBox]::Show(
        "Das Hauptskript fehlt:`n$Kern", 'Universal Update Manager') | Out-Null
    exit 1
}

# ERHOEHUNG ZUR LAUFZEIT PRUEFEN, nicht per `#Requires` (22.09.2026).
#
# Zwei Gruende. Erstens ist `#Requires -RunAsAdministrator` eine Aussage ueber
# die ganze Datei — auch ueber `-NurPruefen`, das nur das Fenster aufbaut und
# nichts anfasst. Der einzige automatische Test dieser Oberflaeche liess sich
# damit ohne erhoehte Sitzung gar nicht starten, und ein Test, den man nicht
# eben laufen lassen kann, laeuft nicht.
#
# Zweitens ist die Meldung von `#Requires` eine rote Konsolenzeile. Die .bat
# startet ohne Konsolenfenster: Wer die Oberflaeche ohne Rechte startet, sieht
# NICHTS. Ein Fenster, das sagt, was fehlt, ist die ehrlichere Antwort.
# Die drei Werkstatt-Laeufe (-NurPruefen, -Abbild, -Selbsttest) aendern
# nichts und duerfen deshalb ohne Rechte laufen. Der Selbsttest hat beim
# ersten Anlauf genau hier gehangen: Er lief in die Meldung hinein, und ein
# MessageBox wartet auf einen Klick, den in einem Testlauf niemand macht.
if (-not $NurPruefen -and -not $Abbild -and -not $Selbsttest) {
    $ich = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $ich.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.MessageBox]::Show(
            "Der Update-Manager braucht Administratorrechte.`n`n" +
            "Am einfachsten über update-manager-gui.bat starten, die fragt die Rechte selbst ab.",
            'Universal Update Manager') | Out-Null
        exit 1
    }
}

# ============================================================================
#  Fensterbeschreibung
#
#  Linksbuendig, nicht zentriert: Eine Liste mit Beschriftungen wird an ihrer
#  linken Kante gelesen, und fuenf mittig schwebende Zeilen zwingen das Auge
#  bei jeder Zeile neu auf die Suche. Mittig steht nur, was fuer sich steht —
#  hier nichts. Die Knopfreihe bleibt rechts und haelt die Hausregel ein:
#  erst der Rueckzug, dann die bestaetigende Handlung, in dieser Reihenfolge
#  auch im Markup, damit Tabulator und Blick dasselbe finden.
# ============================================================================
$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Universal Update Manager" Height="800" Width="820" MinHeight="640" MinWidth="720"
        WindowStartupLocation="CenterScreen" Background="__GRUND__">
  <Window.Resources>
    <!-- Farben an einer Stelle, damit eine Umfaerbung eine Zeile ist -->
    <!-- Die Hausmarke von MelucioLabs ist LILA (Davids Klarstellung
         21.09.2026). In melucio-theme.css steht das als Accent-Token
         (#7C6AF5, hell #A99EF8); das Gruen daneben heisst dort zwar
         "primary", meint aber die Aktionsfarbe des Portals, nicht die
         Marke. Wer nur die Token-Namen liest, greift hier daneben.
         (Kein doppelter Bindestrich in XML-Kommentaren, der bricht sie.)

         Die Werte selbst stehen NICHT mehr hier, sondern als Platzhalter:
         Welche Palette eingesetzt wird, entscheidet weiter unten die
         Windows-Einstellung "App-Modus". Siehe den Block "Hell oder
         dunkel". -->
    <SolidColorBrush x:Key="Akzent"       Color="__AKZENT__"/>
    <SolidColorBrush x:Key="AkzentText"   Color="__AKZENTTEXT__"/>
    <SolidColorBrush x:Key="AkzentKnopf"  Color="__AKZENTKNOPF__"/>
    <SolidColorBrush x:Key="AkzentKnopfH" Color="__AKZENTKNOPFH__"/>
    <SolidColorBrush x:Key="Schrift"      Color="__SCHRIFT__"/>
    <SolidColorBrush x:Key="SchriftLei"   Color="__SCHRIFTLEI__"/>
    <SolidColorBrush x:Key="Karte"        Color="__KARTE__"/>
    <SolidColorBrush x:Key="Tief"         Color="__TIEF__"/>
    <SolidColorBrush x:Key="Bahn"         Color="__BAHN__"/>
    <SolidColorBrush x:Key="Gut"          Color="__GUT__"/>
    <SolidColorBrush x:Key="Schlecht"     Color="__SCHLECHT__"/>
    <SolidColorBrush x:Key="Warn"         Color="__WARN__"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Schrift}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>

    <!-- Der Umschalter. Haken waeren kleiner und wuerden sich wie
         Kleingedrucktes lesen; hier ist der Zustand die Hauptsache. -->
    <Style x:Key="Schalter" TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Schrift}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border Background="Transparent" Padding="0,9" MinHeight="44">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Border x:Name="Bahn" Width="48" Height="26" CornerRadius="13"
                        Background="{StaticResource Bahn}">
                  <Ellipse x:Name="Knauf" Width="20" Height="20" Fill="__KNAUF__"
                           HorizontalAlignment="Left" Margin="3,0,0,0"/>
                </Border>
                <TextBlock x:Name="Symbol" Text="{TemplateBinding Tag}" FontSize="16" Foreground="{StaticResource AkzentText}"
                           FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                           Margin="14,0,8,0" VerticalAlignment="Center"/>
                <ContentPresenter VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bahn" Property="Background" Value="{StaticResource Akzent}"/>
                <Setter TargetName="Knauf" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knauf" Property="Margin" Value="0,0,3,0"/>
                <Setter TargetName="Knauf" Property="Fill" Value="White"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bahn" Property="BorderBrush" Value="{StaticResource AkzentText}"/>
                <Setter TargetName="Bahn" Property="BorderThickness" Value="1"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.65"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Knoepfe: abgerundet, deutliche Flaeche, 44px Mindesthoehe -->
    <Style x:Key="KnopfLeise" TargetType="Button">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="{StaticResource Schrift}"/>
      <Setter Property="Background" Value="__KNOPF__"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MinHeight" Value="44"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Flaeche" Background="{TemplateBinding Background}"
                    CornerRadius="8" Padding="20,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Flaeche" Property="Background" Value="__KNOPFHOVER__"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.65"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="KnopfStark" TargetType="Button" BasedOn="{StaticResource KnopfLeise}">
      <Setter Property="Background" Value="{StaticResource AkzentKnopf}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Flaeche" Background="{TemplateBinding Background}"
                    CornerRadius="8" Padding="24,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Flaeche" Property="Background" Value="{StaticResource AkzentKnopfH}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.65"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Symbole: eine Schrift, ein Strich. Segoe Fluent Icons (Windows 11),
         sonst Segoe MDL2 Assets (Windows 10); keine Emoji. -->
    <Style x:Key="Symbol" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="Foreground" Value="{StaticResource AkzentText}"/>
    </Style>
    <Style x:Key="SymbolKnopf" TargetType="TextBlock" BasedOn="{StaticResource Symbol}">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Foreground" Value="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
    </Style>

    <!-- Kleine Karte, die sich anklicken laesst. Tastaturfokus: Rahmen in der
         Akzentfarbe (die Standard-Fokuslinie fehlt in einer eigenen Vorlage). -->
    <Style x:Key="Kachel" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MinHeight" Value="96"/>
      <Setter Property="Background" Value="{StaticResource Karte}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Flaeche" Background="{TemplateBinding Background}" BorderBrush="Transparent"
                    BorderThickness="2" CornerRadius="10" Padding="14,12">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Top"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Flaeche" Property="Background" Value="__KNOPFHOVER__"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Flaeche" Property="BorderBrush" Value="{StaticResource AkzentText}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Kopf: Markenstreifen links, damit die Farbe nicht nur am Knopf hängt -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,18">
      <Border Width="5" CornerRadius="3" Background="{StaticResource Akzent}" Margin="0,2,14,2"/>
      <StackPanel>
        <!-- WrapPanel, nicht StackPanel: Auf einem schmalen Fenster rutscht
             die Herkunftszeile unter den Titel, statt abgeschnitten zu
             werden. Beide unten ausgerichtet, damit sie auf einer
             Schriftlinie sitzen. -->
        <WrapPanel Orientation="Horizontal">
          <TextBlock Text="Universal Update Manager" FontSize="23" FontWeight="SemiBold"
                     Foreground="{StaticResource AkzentText}" VerticalAlignment="Bottom"/>
          <TextBlock FontSize="12" Foreground="{StaticResource SchriftLei}"
                     Margin="12,0,0,5" VerticalAlignment="Bottom">
            <Run Text="bereitgestellt von "/><Hyperlink x:Name="LinkMelucio"
                 NavigateUri="https://meluciolabs.de"
                 Foreground="{StaticResource AkzentText}">MelucioLabs</Hyperlink>
          </TextBlock>
        </WrapPanel>
        <TextBlock x:Name="TxtHardware" Text="Hardware wird erkannt …" FontSize="12"
                   Foreground="{StaticResource SchriftLei}" Margin="0,5,0,0" TextWrapping="Wrap"/>
        <!-- Der nächtliche Lauf ist sonst unsichtbar: Er läuft ohne Fenster,
             und wer nicht von sich aus das Protokoll öffnet, erfährt nie, ob
             er etwas getan hat oder seit Wochen scheitert. -->
        <TextBlock x:Name="TxtLetzterLauf" Text="" FontSize="12"
                   Foreground="{StaticResource SchriftLei}" Margin="0,3,0,0" TextWrapping="Wrap"/>
        <!-- Neue Fassung (SELBST-UPDATE.md): erst sichtbar, wenn die
             Tagesabfrage eine neuere gefunden hat. Kein Dialog, der sich vor
             die Arbeit schiebt. -->
        <WrapPanel x:Name="ZeileNeueFassung" Orientation="Horizontal" Margin="0,8,0,0" Visibility="Collapsed">
          <TextBlock x:Name="TxtNeueFassung" FontSize="12" FontWeight="SemiBold"
                     Foreground="{StaticResource AkzentText}" VerticalAlignment="Center"
                     Margin="0,0,12,0" TextWrapping="Wrap"/>
          <TextBlock FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0">
            <Hyperlink x:Name="LinkNeueFassung" NavigateUri="https://meluciolabs.de/update"
                       Foreground="{StaticResource AkzentText}">Was ist neu?</Hyperlink>
          </TextBlock>
          <TextBlock x:Name="TxtLinkSeite" FontSize="12" VerticalAlignment="Center" Margin="0,0,12,0">
            <Hyperlink x:Name="LinkUpdateSeite" NavigateUri="https://meluciolabs.de/update"
                       Foreground="{StaticResource AkzentText}">Herunterladen</Hyperlink>
          </TextBlock>
          <Button x:Name="BtnNeueFassung" Style="{StaticResource KnopfLeise}" Margin="0,0,8,0"
                  Content="Neue Version installieren" Visibility="Collapsed"/>
          <Button x:Name="BtnFassungSpaeter" Style="{StaticResource KnopfLeise}" Margin="0" Content="Später"/>
        </WrapPanel>
      </StackPanel>
    </StackPanel>

    <StackPanel Grid.Row="1">
    <!-- Standardansicht kurz (Davids Frage 08.10.2026, ob das Fenster so
         ausfuehrlich zeigen muss, was es tut): eine Zahl, ein Satz. Alles
         Weitere steht unter "Details". Farbe und Zeichen tragen zusammen. -->
    <Grid Margin="0,0,0,10">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Border x:Name="KarteErgebnis" Grid.Column="0" Background="{StaticResource Karte}" CornerRadius="10" Margin="0,0,10,0" MinHeight="96">
        <Grid>
          <Border x:Name="StreifenErgebnis" Width="5" HorizontalAlignment="Left" CornerRadius="10,0,0,10"
                  Background="{StaticResource SchriftLei}"/>
          <StackPanel Margin="18,12,12,12">
            <TextBlock x:Name="TxtIconErgebnis" Style="{StaticResource Symbol}" Text="&#xE895;"/>
            <TextBlock x:Name="TxtZahl" Text="" FontSize="26" FontWeight="SemiBold" Margin="0,6,0,0"
                       Foreground="{StaticResource SchriftLei}" AutomationProperties.Name="Anzahl"/>
            <TextBlock Text="Updates im letzten Lauf" FontSize="12" Foreground="{StaticResource SchriftLei}" TextWrapping="Wrap"/>
          </StackPanel>
        </Grid>
      </Border>
      <Button x:Name="KachelEinstellungen" Grid.Column="1" Style="{StaticResource Kachel}" Margin="0,0,10,0"
              AutomationProperties.Name="Einstellungen ein- oder ausblenden">
        <StackPanel>
          <TextBlock Style="{StaticResource Symbol}" Text="&#xE713;"/>
          <TextBlock x:Name="TxtKachelEinst" Text="5 von 5" FontSize="20" FontWeight="SemiBold" Margin="0,8,0,0" Foreground="{StaticResource Schrift}"/>
          <TextBlock Text="Quellen aktiv" FontSize="12" Foreground="{StaticResource SchriftLei}"/>
        </StackPanel>
      </Button>
      <Button x:Name="KachelVerlauf" Grid.Column="2" Style="{StaticResource Kachel}" Margin="0,0,10,0"
              AutomationProperties.Name="Verlauf dieser Sitzung ein- oder ausblenden">
        <StackPanel>
          <TextBlock Style="{StaticResource Symbol}" Text="&#xE81C;"/>
          <TextBlock Text="Verlauf" FontSize="20" FontWeight="SemiBold" Margin="0,8,0,0" Foreground="{StaticResource Schrift}"/>
          <TextBlock x:Name="TxtKachelVerlauf" Text="dieser Sitzung" FontSize="12" Foreground="{StaticResource SchriftLei}"/>
        </StackPanel>
      </Button>
      <Button x:Name="KachelProtokolle" Grid.Column="3" Style="{StaticResource Kachel}"
              AutomationProperties.Name="Protokoll ein- oder ausblenden">
        <StackPanel>
          <TextBlock Style="{StaticResource Symbol}" Text="&#xE8A5;"/>
          <TextBlock x:Name="TxtKachelProto" Text="Protokoll" FontSize="20" FontWeight="SemiBold" Margin="0,8,0,0" Foreground="{StaticResource Schrift}"/>
          <TextBlock x:Name="TxtKachelProtoZeit" Text="im Protokoll" FontSize="12" Foreground="{StaticResource SchriftLei}"/>
        </StackPanel>
      </Button>
    </Grid>
    <StackPanel Margin="2,0,0,14">
      <TextBlock x:Name="TxtErgebnis" Text="Wird gelesen …" FontSize="16" TextWrapping="Wrap"
                 Foreground="{StaticResource Schrift}"/>
      <TextBlock x:Name="TxtErgebnisZeit" Text="" FontSize="12" Margin="0,3,0,0" TextWrapping="Wrap"
                 Foreground="{StaticResource SchriftLei}"/>
    </StackPanel>
    <!-- Die Schalter stehen vorbelegt auf "alles" und sind selten anzufassen:
         zu, bis jemand sie sucht. -->
    <StackPanel x:Name="PanelEinstellungen" Visibility="Collapsed" Margin="0,0,0,12">
    <Border Background="{StaticResource Karte}" CornerRadius="10" Padding="20,14" Margin="0,8,0,0">
      <StackPanel>
        <TextBlock Text="Was soll geprüft werden?" FontSize="14" FontWeight="SemiBold"
                   Foreground="{StaticResource SchriftLei}" Margin="0,0,0,4"/>
        <CheckBox x:Name="ChkWinget"  Style="{StaticResource Schalter}" Tag="&#xE8F1;" IsChecked="True"
                  Content="Winget: Programme aus dem Microsoft-Paketverzeichnis"/>
        <CheckBox x:Name="ChkChoco"   Style="{StaticResource Schalter}" Tag="&#xE7B8;" IsChecked="True"
                  Content="Chocolatey: Programme aus dem Community-Verzeichnis"/>
        <CheckBox x:Name="ChkWindows" Style="{StaticResource Schalter}" Tag="&#xE770;" IsChecked="True"
                  Content="Windows Update: System und Treiber"/>
        <CheckBox x:Name="ChkStore"   Style="{StaticResource Schalter}" Tag="&#xE8A1;" IsChecked="True"
                  Content="Microsoft Store: Apps im Hintergrund anstoßen"/>
        <CheckBox x:Name="ChkTreiber" Style="{StaticResource Schalter}" Tag="&#xE950;" IsChecked="True"
                  Content="Hersteller-Werkzeuge: nur erkannte Hardware"/>
        <!-- Die nächtliche Uhrzeit gehört hierher und nicht ins alte
             Konsolenmenü: Wer hier steht, will einstellen, was der Manager
             tut — und die Frage "wann von selbst" ist dieselbe Frage wie
             "was". Sie steht am Ende des Blocks, weil sie seltener
             angefasst wird als die Schalter darüber. -->
        <Border Height="1" Background="{StaticResource Bahn}" Opacity="0.35" Margin="0,14,0,10"/>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Nächtlich um" FontSize="14" VerticalAlignment="Center" Foreground="{StaticResource Schrift}"/>
          <TextBox x:Name="TxtZeit" Text="04:00" Width="72" Margin="10,0,0,0" MinHeight="36"
                   FontSize="14" MaxLength="5" TextAlignment="Center"
                   VerticalContentAlignment="Center" BorderThickness="0"
                   Background="{StaticResource Tief}" Foreground="{StaticResource Schrift}"
                   CaretBrush="{StaticResource Schrift}" Padding="6,4"/>
          <TextBlock Text="Uhr" FontSize="14" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{StaticResource Schrift}"/>
          <Button x:Name="BtnZeit" Style="{StaticResource KnopfLeise}"
                  Margin="14,0,0,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE73E;"/>
            <TextBlock x:Name="TxtBtnZeit" Text="Übernehmen" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
        </StackPanel>
        <TextBlock x:Name="TxtAufgabe" Text="" FontSize="12" Margin="0,8,0,0"
                   TextWrapping="Wrap" Foreground="{StaticResource SchriftLei}"/>
      </StackPanel>
    </Border>
    </StackPanel>
    </StackPanel>

    <!-- Details starten geschlossen (Hausregel: Aufklappbares ist zu). Hier
         liegen der Verlauf dieser Sitzung und das Protokoll, schoen gesetzt. -->
    <Grid x:Name="PanelDetails" Grid.Row="2" Visibility="Collapsed">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <WrapPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
          <Button x:Name="BtnAnsichtVerlauf" Style="{StaticResource KnopfLeise}" Margin="0,0,8,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE81C;"/>
            <TextBlock x:Name="TxtBtnAnsichtVerlauf" Text="Verlauf" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
          <Button x:Name="BtnAnsichtProtokoll" Style="{StaticResource KnopfLeise}" Margin="0,0,8,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE8A5;"/>
            <TextBlock x:Name="TxtBtnAnsichtProtokoll" Text="Protokoll" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
          <Button x:Name="BtnFilterAlles" Style="{StaticResource KnopfLeise}" Margin="16,0,8,0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE8FD;"/>
            <TextBlock x:Name="TxtBtnFilterAlles" Text="Alles" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
          <Button x:Name="BtnFilterFehler" Style="{StaticResource KnopfLeise}" Margin="0,0,8,0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE783;"/>
            <TextBlock x:Name="TxtBtnFilterFehler" Text="Fehler (0)" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
        </WrapPanel>
        <Border x:Name="PanelVerlauf" Grid.Row="1" Background="{StaticResource Tief}" CornerRadius="10" Padding="4" MinHeight="120">
          <ScrollViewer x:Name="ScrollProtokoll" VerticalScrollBarVisibility="Auto">
            <TextBox x:Name="TxtProtokoll" Background="Transparent" Foreground="__PROTOKOLL__"
                     BorderThickness="0" FontFamily="Cascadia Mono, Consolas" FontSize="12"
                     IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" Padding="12,8"
                     Text="Bereit. Nichts wird verändert, bevor eine Schaltfläche gedrückt wird."/>
          </ScrollViewer>
        </Border>
        <Border x:Name="PanelProtokoll" Grid.Row="1" Background="{StaticResource Tief}" CornerRadius="10" Padding="4"
                MinHeight="120" Visibility="Collapsed">
          <RichTextBox x:Name="RtfProtokoll" Background="Transparent" Foreground="__PROTOKOLL__"
                       BorderThickness="0" IsReadOnly="True" FontFamily="Segoe UI" FontSize="13"
                       VerticalScrollBarVisibility="Auto" Padding="8,4"
                       AutomationProperties.Name="Protokoll"/>
        </Border>
      </Grid>
    </Grid>

    <ProgressBar x:Name="Fortschritt" Grid.Row="3" Height="5" Margin="0,14,0,0"
                 IsIndeterminate="False" Background="{StaticResource Karte}"
                 Foreground="{StaticResource AkzentText}" BorderThickness="0"/>

    <!-- Live-Fenster: die letzten zehn Zeilen des laufenden Auftrags, neueste
         unten, aeltere rutschen hoch. Nur waehrend eines Laufs sichtbar. Das
         grosse Feld darueber behaelt den vollen Verlauf. -->
    <Border x:Name="LiveRahmen" Grid.Row="4" Visibility="Collapsed" Background="{StaticResource Tief}"
            CornerRadius="10" Padding="4" Height="196" Margin="0,10,0,0">
      <TextBlock x:Name="TxtLive" Foreground="__PROTOKOLL__" FontFamily="Cascadia Mono, Consolas"
                 FontSize="12" LineHeight="17" LineStackingStrategy="BlockLineHeight"
                 TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" Padding="12,8"
                 AutomationProperties.Name="Live-Ausgabe"/>
    </Border>

    <Grid Grid.Row="5" Margin="0,16,0,0">
      <TextBlock x:Name="TxtStatus" Text="" VerticalAlignment="Center"
                 Foreground="{StaticResource SchriftLei}" FontSize="12" TextWrapping="Wrap"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnProtokoll" Style="{StaticResource KnopfLeise}">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE8A5;"/>
            <TextBlock x:Name="TxtBtnProtokoll" Text="Protokoll" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnSchliessen" Style="{StaticResource KnopfLeise}">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE711;"/>
            <TextBlock x:Name="TxtBtnSchliessen" Text="Schließen" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnPruefen" Style="{StaticResource KnopfLeise}">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE7B3;"/>
            <TextBlock x:Name="TxtBtnPruefen" Text="Nur nachsehen" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnStart" Style="{StaticResource KnopfStark}">
          <StackPanel Orientation="Horizontal">
            <TextBlock Style="{StaticResource SymbolKnopf}" Text="&#xE895;"/>
            <TextBlock x:Name="TxtBtnStart" Text="Aktualisieren" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
          </StackPanel>
        </Button>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
'@

# ============================================================================
#  Hell oder dunkel — was Windows sagt (22.09.2026)
#
#  Das Fenster war fest dunkel. Wer sein Gerät auf Hell gestellt hat, bekam
#  als einziges Fenster auf dem Schirm eine schwarze Fläche, und im
#  Sonnenlicht liest sich das schlecht. Die Hausregel für Webseiten (System
#  ist die Vorgabe, nicht Hell und nicht Dunkel) gilt hier genauso; Windows
#  hält die Antwort in der Registry unter "AppsUseLightTheme".
#
#  Entschieden wird EINMAL beim Öffnen. Ein Fenster, das sich mitten im Lauf
#  umfärbt, ist eine Spielerei, die keiner braucht — und der Lauf dauert
#  Minuten, nicht Stunden.
#
#  GEMESSEN, NICHT GESCHÄTZT (Hausregel: 4,5:1 für Fließtext). Dabei fiel
#  auch ein alter Fehler im dunklen Fenster auf: Weiße Schrift auf dem
#  Marken-Lila #7C6AF5 misst 4,01:1 und reißt die Grenze. Deshalb gibt es
#  jetzt drei Akzente statt einem:
#    Akzent       #7C6AF5   nur Flächen und Ränder, nie Schrift
#    AkzentText   hell #5B47D6 (6,33:1 auf Weiß) / dunkel #A99EF8 (6,72:1)
#    AkzentKnopf  #5B47D6, weiße Schrift darauf misst 6,33:1
# ============================================================================
$AppsHell = $false
if ($Erscheinung -eq 'hell') {
    $AppsHell = $true
} elseif ($Erscheinung -eq 'system') {
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                                -Name 'AppsUseLightTheme' -ErrorAction Stop
        $AppsHell = ($reg.AppsUseLightTheme -eq 1)
    } catch {
        # Kein Wert, kein Drama: Ohne Auskunft bleibt es dunkel wie bisher.
    }
}

$Palette = if ($AppsHell) {
    @{ GRUND = '#FFFAFAFC'; KARTE = '#FFFFFFFF'; TIEF = '#FFF1F1F4'
       SCHRIFT = '#FF17171B'; SCHRIFTLEI = '#FF5A5A66'; PROTOKOLL = '#FF2A2A33'
       AKZENT = '#FF7C6AF5'; AKZENTTEXT = '#FF5B47D6'
       AKZENTKNOPF = '#FF5B47D6'; AKZENTKNOPFH = '#FF4C3AC0'
       BAHN = '#FF7A7A8E'; KNAUF = '#FFFFFFFF'; KNOPF = '#FFE8E8EE'; KNOPFHOVER = '#FFDCDCE6'
       GUT = '#FF166534'; SCHLECHT = '#FFB91C1C'; WARN = '#FF92400E' }
} else {
    @{ GRUND = '#FF17171B'; KARTE = '#FF22222A'; TIEF = '#FF101014'
       SCHRIFT = '#FFF2F2F5'; SCHRIFTLEI = '#FF9A9AA8'; PROTOKOLL = '#FFC8C8D2'
       AKZENT = '#FF7C6AF5'; AKZENTTEXT = '#FFA99EF8'
       AKZENTKNOPF = '#FF5B47D6'; AKZENTKNOPFH = '#FF6F5BE4'
       BAHN = '#FF5A5A6C'; KNAUF = '#FFE6E6EC'; KNOPF = '#FF2E2E38'; KNOPFHOVER = '#FF3A3A46'
       GUT = '#FF4ADE80'; SCHLECHT = '#FFF87171'; WARN = '#FFFBBF24' }
}
foreach ($schluessel in $Palette.Keys) {
    $xamlText = $xamlText.Replace("__${schluessel}__", $Palette[$schluessel])
}
# Ein vergessener Platzhalter faellt sonst erst als XAML-Fehler auf, und der
# nennt nur eine Zeilennummer.
if ($xamlText -match '__[A-Z]+__') {
    throw "Farbe ohne Wert in der Fensterbeschreibung: $($Matches[0])"
}
[xml]$xaml = $xamlText

$fenster = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$E = @{}
foreach ($name in @('TxtHardware','TxtLetzterLauf','LinkMelucio','ChkWinget','ChkChoco','ChkWindows','ChkStore','ChkTreiber',
                    'TxtProtokoll','ScrollProtokoll','LiveRahmen','TxtLive','Fortschritt','TxtStatus','TxtZeit','BtnZeit','TxtAufgabe',
                    'BtnProtokoll','BtnSchliessen','BtnPruefen','BtnStart',
                    'ZeileNeueFassung','TxtNeueFassung','LinkNeueFassung','TxtLinkSeite','LinkUpdateSeite',
                    'BtnNeueFassung','BtnFassungSpaeter',
                    'PanelEinstellungen','KarteErgebnis','StreifenErgebnis','TxtZahl','TxtErgebnis','TxtErgebnisZeit','PanelDetails',
                    'TxtIconErgebnis','KachelEinstellungen','KachelVerlauf','KachelProtokolle','TxtKachelEinst','TxtKachelVerlauf',
                    'TxtKachelProto','TxtKachelProtoZeit','TxtBtnFilterFehler',
                    'BtnAnsichtVerlauf','BtnAnsichtProtokoll','BtnFilterAlles','BtnFilterFehler',
                    'PanelVerlauf','PanelProtokoll','RtfProtokoll')) {
    $E[$name] = $fenster.FindName($name)
    if ($null -eq $E[$name]) { throw "Element fehlt im XAML: $name" }
}

# ============================================================================
#  Hilfsmittel
# ============================================================================

function Schreibe {
    param([string]$Zeile)
    if ($Zeile -match '^(Aktualisiert|Updated):.*\((\d+) [^)]*\)\s*$') { $script:LaufAnzahl += [int]$Matches[2] }
    $E.TxtProtokoll.AppendText("`r`n$Zeile")
    $E.ScrollProtokoll.ScrollToEnd()
    # Live-Fenster: nur die letzten LIVE_ZEILEN, leere Zeilen zaehlen nicht.
    if ($Zeile.Trim()) {
        $Live.Add($Zeile)
        while ($Live.Count -gt $LIVE_ZEILEN) { $Live.RemoveAt(0) }
        $E.TxtLive.Text = ($Live -join "`n")
    }
    # Das Fenster einmal durchatmen lassen, sonst malt Windows waehrend eines
    # laengeren Laufs den Grauschleier "reagiert nicht" darueber. Ein leerer
    # Auftrag auf der Background-Ebene arbeitet alles ab, was an Zeichnen
    # ansteht — das WPF-Gegenstueck zu DoEvents, ohne WinForms zu laden.
    $fenster.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

function Setze-Beschaeftigt {
    param([bool]$Ja, [string]$Text = '', [switch]$Gut, [switch]$Schlecht)
    $E.Fortschritt.IsIndeterminate = $Ja
    if ($Ja) {
        $Live.Clear(); $E.TxtLive.Text = ''
        $script:LaufAnzahl = 0
        # Das Live-Fenster gehoert zu den Details: nur zeigen, wenn die offen sind.
        $E.LiveRahmen.Visibility = if (Details-Offen) { 'Visible' } else { 'Collapsed' }
        Zeige-Ergebnis -Zahl ([string][char]0x2026) -Satz 'Läuft …' -Zeit 'Das dauert einige Minuten.' -Ton 'neutral'
    }
    Aktualisiere-Kacheln
    $E.TxtStatus.Text = $Text
    $E.TxtStatus.Foreground = if ($Schlecht) { $fenster.FindResource('Schlecht') }
                              elseif ($Gut)  { $fenster.FindResource('Gut') }
                              else           { $fenster.FindResource('SchriftLei') }
    foreach ($n in @('BtnStart','BtnPruefen','ChkWinget','ChkChoco','ChkWindows','ChkStore','ChkTreiber')) {
        $E[$n].IsEnabled = -not $Ja
    }
}

# -- Die Arbeit gehoert NICHT auf den Zeichen-Thread ------------------------
#
# Der erste Anlauf las die Ausgabe des Kindprozesses in einer Schleife direkt
# im Klick-Ereignis. Solange ReadLine wartet - und winget wartet gern eine
# Minute, bevor die erste Zeile kommt - verarbeitet das Fenster keine
# Nachrichten mehr: Windows legt den Grauschleier darueber und schreibt
# "Keine Rueckmeldung" in den Titel (Davids Bild, 21.09.2026). Es lief in
# Wahrheit alles, man sah es nur nicht.
#
# Jetzt laeuft die Prozesskette in einem eigenen Runspace und schiebt ihre
# Zeilen in eine nebenlaeufige Warteschlange. Ein DispatcherTimer im
# Fenster-Thread leert sie alle 150 ms. Nichts blockiert, und die
# WPF-Objekte werden weiterhin nur aus ihrem eigenen Thread angefasst - die
# Warteschlange ist bewusst das einzige Gemeinsame.
$Warteschlange = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$LIVE_ZEILEN = 10
$Live = New-Object System.Collections.Generic.List[string]
$Lauf = @{ ps = $null; rs = $null; kind = 0; begonnen = $null; art = '' }

# Marken, die der Hintergrund durch die Warteschlange schickt. Als Text, weil
# die Warteschlange nur Text traegt und ein zweiter Kanal mehr kosten wuerde,
# als er einbraechte.
$MARKE_FERTIG = '::fertig::'
$MARKE_KIND   = '::kind::'

function Baue-KernArgumente {
    <#
        Die Argumentzeile fuer den Kindprozess, an EINER Stelle und pruefbar.

        -Command statt -File, und die Kodierung als ERSTE Anweisung.

        Ein Kindprozess OHNE Konsole schreibt seine Fehler in der
        OEM-Codepage (hier 850), waehrend die Ausgaben des Skripts selbst
        UTF-8 sind, sobald es [Console]::OutputEncoding gesetzt hat. Die
        Oberflaeche las alles als UTF-8 - daher Umlaute mal richtig, mal
        als Kaestchen (Davids Befund 21.09.2026).

        Nachgemessen, ohne Konsole, dieselbe Meldung dreimal gelesen:
          -File,    gelesen UTF-8  -> "ausgef?hrt"   (kaputt)
          -File,    gelesen OEM850 -> "ausgefuehrt"  (gut, aber dann waeren
                                      die Skripttexte kaputt)
          -Command mit Kodierung zuerst, gelesen UTF-8 -> alles gut

        Der Grund: Mit -Command laeuft das Setzen der Kodierung, BEVOR das
        Skript geladen wird. Meldungen, die dabei entstehen (fehlende
        Erhoehung, Parameterfehler), sind dann schon UTF-8.

        DIE NAMEN STEHEN IN ANFUEHRUNGSZEICHEN (03.10.2026). Ohne sie liest
        PowerShell `winget,choco` in einer -Command-Zeile als Liste, und
        `[string]$Auftrag` bekommt "winget choco". Der Kern kannte diesen
        einen Namen nicht: Zwei umgelegte Schalter ergaben "Unbekannter
        Auftrag", und das Fenster meldete trotzdem "Fertig". Die Probe
        (probe.ps1) startet genau diese Zeile gegen eine Attrappe.
    #>
    param([string]$KernPfad, [string[]]$Namen)

    $vorlauf = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; '
    # Ein Hochkomma im Pfad oder Namen wuerde die Zeichenkette beenden.
    $pfad  = $KernPfad.Replace("'", "''")
    $liste = (@($Namen) -join ',').Replace("'", "''")
    # `exit $LASTEXITCODE` am Ende: Mit -Command reicht PowerShell den
    # Exit-Code eines gerufenen Skripts nicht verlaesslich durch (je nach
    # Fassung kommt 0 oder 1 an). Das Fenster braucht aber genau diese Zahl,
    # um zwischen "fertig" und "mit Fehlern" zu unterscheiden.
    #
    # Kam das Skript gar nicht bis zu einem `exit` (Datei fehlt, Syntax- oder
    # Parameterfehler), gibt es keinen Code. Das ist dann 1 und nicht 0:
    # Ein Lauf, der nicht stattfand, ist kein gelungener.
    return '-NoProfile -ExecutionPolicy Bypass -Command "' + $vorlauf +
           "& '" + $pfad + "' -Auftrag '" + $liste + "'; " +
           'if ($null -eq $LASTEXITCODE) { exit 1 }; exit $LASTEXITCODE' + '"'
}

function Starte-Kette {
    param([object[]]$Auftraege, [string]$Art)

    $Lauf.begonnen = Get-Date
    $Lauf.art = $Art

    # Hier und nicht im Hintergrund zusammengebaut: Der Runspace unten kennt
    # die Funktionen dieses Skripts nicht, nur die Variablen, die er bekommt.
    $argumente = Baue-KernArgumente -KernPfad $Kern -Namen @($Auftraege | ForEach-Object { $_.Name })

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Warteschlange', $Warteschlange)
    $rs.SessionStateProxy.SetVariable('Argumente', $argumente)
    $rs.SessionStateProxy.SetVariable('Exe', (Get-Process -Id $PID).Path)
    $rs.SessionStateProxy.SetVariable('MARKE_FERTIG', $MARKE_FERTIG)
    $rs.SessionStateProxy.SetVariable('MARKE_KIND', $MARKE_KIND)

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        # EIN Prozess fuer alle gewaehlten Aufgaben, keine Schleife mehr.
        #
        # Frueher startete die Oberflaeche einen Prozess JE Aufgabe. Dann
        # laufen Konfiguration, Voraussetzungen und Hardware-Erkennung jedes
        # Mal neu, und derselbe achtzeilige Block steht fuenfmal im Protokoll
        # (Davids Befund 21.09.2026). Der Kern kann die Namen jetzt als Liste
        # entgegennehmen und macht die Vorbereitung einmal.
        #
        # Eigene Trenner braucht es dabei nicht: Die Abschnittsueberschriften
        # kommen aus dem Kern selbst ("WINGET UPDATES").
        #
        # Die Argumentzeile kommt fertig herein (Baue-KernArgumente).
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = $Exe
        $psi.Arguments = $Argumente
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

        try {
            $prozess = [System.Diagnostics.Process]::Start($psi)
        } catch {
            $Warteschlange.Enqueue('[Fehler] Start fehlgeschlagen: ' + $_.Exception.Message)
            $Warteschlange.Enqueue($MARKE_FERTIG + '-1')
            return
        }
        $Warteschlange.Enqueue($MARKE_KIND + $prozess.Id)
        # Eingabe sofort schliessen: Fragt der Kern wider Erwarten doch,
        # bekommt er ein Dateiende statt ewiger Stille.
        try { $prozess.StandardInput.Close() } catch { }

        while (-not $prozess.StandardOutput.EndOfStream) {
            $Warteschlange.Enqueue($prozess.StandardOutput.ReadLine())
        }
        $fehler = $prozess.StandardError.ReadToEnd()
        $prozess.WaitForExit()
        if ($fehler -and $fehler.Trim()) {
            $Warteschlange.Enqueue('[Fehler] ' + $fehler.Trim())
        }

        # Der Exit-Code faehrt in der Marke mit. Bis zum 03.10.2026 wurde er
        # nie gelesen: Das Fenster meldete "Fertig", egal was der Kern sagte.
        $Warteschlange.Enqueue($MARKE_FERTIG + $prozess.ExitCode)
    })

    $Lauf.ps = $ps
    $Lauf.rs = $rs
    [void]$ps.BeginInvoke()
}

# Welche Aufgaben sind umgelegt? Die Reihenfolge ist die des Fensters, damit
# das Protokoll so laeuft, wie die Liste aussieht.
#
# Diese Funktion ging beim Umbau auf den Hintergrund-Runspace verloren (sie
# stand im ersetzten Block) - der Klick auf "Aktualisieren" fand sie nicht
# mehr, und weil $ErrorActionPreference auf 'Stop' steht, beendete die
# Ausnahme gleich das ganze Skript: Das Fenster verschwand (21.09.2026).
function Gewaehlte-Auftraege {
    $liste = @()
    if ($E.ChkWinget.IsChecked)  { $liste += @{ Name = 'winget';  Titel = 'Winget' } }
    if ($E.ChkChoco.IsChecked)   { $liste += @{ Name = 'choco';   Titel = 'Chocolatey' } }
    if ($E.ChkWindows.IsChecked) { $liste += @{ Name = 'windows'; Titel = 'Windows Update' } }
    if ($E.ChkStore.IsChecked)   { $liste += @{ Name = 'store';   Titel = 'Microsoft Store' } }
    if ($E.ChkTreiber.IsChecked) { $liste += @{ Name = 'treiber'; Titel = 'Hersteller-Werkzeuge' } }
    return $liste
}

function Bilde-Abschluss {
    <#
        Was am Ende eines Laufs im Fenster steht — abhaengig davon, wie der
        Kern ausging.

        WARUM (03.10.2026). Das Fenster schrieb bis dahin IMMER "Fertig" in
        Gruen. Der Exit-Code des Kerns wurde nie gelesen, und der Kern gab im
        Auftragsmodus ohnehin immer 0 zurueck. Ein Lauf, der an "Unbekannter
        Auftrag" scheiterte oder in dem winget nicht antwortete, sah im
        Fenster genauso aus wie ein gelungener. Gruen hiess nur, dass der
        Prozess zu Ende war.

        Die Codes des Kerns: 0 gut · 5 gelaufen, aber mit Fehlern · 2
        unbekannter Auftrag · 4 keine Rechte · 1 abgebrochen. Alles ausser 0
        ist rot und verweist aufs Protokoll.
    #>
    param([string]$Art, [int]$ExitCode, [double]$Minuten)

    if ($ExitCode -eq 0) {
        if ($Art -eq 'pruefen') {
            return @{ Gut = $true; Status = 'Nachgesehen. Es wurde nichts verändert.'
                      Protokoll = 'Nachgesehen. Es wurde nichts veraendert.' }
        }
        return @{ Gut = $true; Status = "Fertig nach $Minuten Minuten."
                  Protokoll = "Fertig nach $Minuten Minuten. Einzelheiten im Protokoll." }
    }

    $was = switch ($ExitCode) {
        5       { 'Mit Fehlern beendet' }
        2       { 'Nicht gestartet: unbekannter Auftrag' }
        4       { 'Nicht gestartet: Administratorrechte fehlen' }
        default { "Abgebrochen (Code $ExitCode)" }
    }
    if ($Art -eq 'pruefen') { $was = "Nachsehen unvollständig. $was" }
    return @{ Gut = $false; Status = "$was. Einzelheiten im Protokoll."
              Protokoll = "$was nach $Minuten Minuten (Code $ExitCode). Einzelheiten ueber den Knopf Protokoll." }
}

function Raeume-Lauf-Auf {
    if ($Lauf.ps) { try { $Lauf.ps.Dispose() } catch { } ; $Lauf.ps = $null }
    if ($Lauf.rs) { try { $Lauf.rs.Close(); $Lauf.rs.Dispose() } catch { } ; $Lauf.rs = $null }
    $Lauf.kind = 0
}

# Der Taktgeber im Fenster-Thread: holt, was da ist, und schreibt es hin.
$Takt = New-Object System.Windows.Threading.DispatcherTimer
$Takt.Interval = [TimeSpan]::FromMilliseconds(150)
$Takt.Add_Tick({
  try {
    $zeile = $null
    # Pro Takt begrenzt viele Zeilen, sonst wird der Taktgeber bei einer sehr
    # gespraechigen Ausgabe selbst zum Blockierer.
    for ($i = 0; $i -lt 200; $i++) {
        if (-not $Warteschlange.TryDequeue([ref]$zeile)) { break }

        if ($zeile -and $zeile.StartsWith($MARKE_FERTIG)) {
            $Takt.Stop()
            Raeume-Lauf-Auf
            $dauer = [math]::Round(((Get-Date) - $Lauf.begonnen).TotalMinutes, 1)
            # Ohne lesbaren Code gilt der Lauf NICHT als gelungen: Wer nicht
            # weiss, wie es ausging, meldet kein Gruen.
            $code = -1
            [void][int]::TryParse($zeile.Substring($MARKE_FERTIG.Length), [ref]$code)
            $schluss = Bilde-Abschluss -Art $Lauf.art -ExitCode $code -Minuten $dauer
            Schreibe ''
            Schreibe $schluss.Protokoll
            if ($schluss.Gut) { Setze-Beschaeftigt $false $schluss.Status -Gut }
            else              { Setze-Beschaeftigt $false $schluss.Status -Schlecht }
            Zeige-LaufErgebnis $schluss $Lauf.art $script:LaufAnzahl $dauer
            return
        }

        if ($zeile -and $zeile.StartsWith($MARKE_KIND)) {
            $Lauf.kind = [int]$zeile.Substring($MARKE_KIND.Length)
            continue
        }

        Schreibe $zeile
    }
  } catch {
    # Ein Fehler beim Anzeigen darf den Lauf nicht mitreissen.
    $Takt.Stop()
    try { $E.TxtStatus.Text = "Anzeige gestört: $($_.Exception.Message)" } catch { }
  }
})

# ============================================================================
#  Verhalten
# ============================================================================

# Jede Aktion in einem Netz. Ohne das beendet eine einzige Ausnahme - bei
# $ErrorActionPreference = 'Stop' reicht eine fehlende Funktion - das Skript,
# und das Fenster ist einfach weg, ohne ein Wort. Genau so ist es am
# 21.09.2026 passiert. Ein Werkzeug darf kaputtgehen; es darf nur nicht
# verschwinden, ohne zu sagen, woran.
function Fuehre-Sicher-Aus {
    param([scriptblock]$Tun, [string]$Was)
    try {
        & $Tun
    } catch {
        $Takt.Stop()
        Raeume-Lauf-Auf
        Schreibe ''
        Schreibe "[Fehler] $Was ist fehlgeschlagen: $($_.Exception.Message)"
        if ($_.InvocationInfo) { Schreibe "  $($_.InvocationInfo.PositionMessage.Trim())" }
        Setze-Beschaeftigt $false "Fehlgeschlagen — Einzelheiten stehen oben."
        try { Write-EigenesLog $_ } catch { }
    }
}

# Was schiefging, gehoert auch in die Protokolldatei: Wer das Fenster schon
# zugemacht hat, findet es sonst nirgends wieder.
function Write-EigenesLog {
    param($Fehler)
    $ordner = Split-Path $LogPfad
    if (-not (Test-Path $ordner)) { New-Item -ItemType Directory -Force -Path $ordner | Out-Null }
    $zeile = '[{0}] [GUI] [ERROR] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Fehler.Exception.Message
    Add-Content -Path $LogPfad -Value $zeile -Encoding UTF8
}

$E.BtnStart.Add_Click({
    Fuehre-Sicher-Aus -Was 'Aktualisieren' -Tun {
        $auftraege = Gewaehlte-Auftraege
        if ($auftraege.Count -eq 0) {
            $E.TxtStatus.Text = 'Nichts ausgewählt.'
            return
        }
        Setze-Beschaeftigt $true 'Läuft …'
        Starte-Kette -Auftraege $auftraege -Art 'alles'
        $Takt.Start()
    }
})

$E.BtnPruefen.Add_Click({
    Fuehre-Sicher-Aus -Was 'Nachsehen' -Tun {
        Setze-Beschaeftigt $true 'Sieht nach …'
        Starte-Kette -Auftraege @(@{ Name = 'pruefen'; Titel = 'Was steht an' }) -Art 'pruefen'
        $Takt.Start()
    }
})

$E.BtnZeit.Add_Click({
    $zeit = "$($E.TxtZeit.Text)".Trim()
    # Erst hier pruefen, damit die Rueckmeldung sofort im Fenster steht statt
    # erst nach dem Start eines Prozesses. Der Kern prueft trotzdem noch
    # einmal: Er wird auch von woanders gerufen.
    if ($zeit -notmatch '^([01]?\d|2[0-3]):([0-5]\d)$') {
        $E.TxtAufgabe.Text = 'Uhrzeit bitte als HH:MM angeben, zum Beispiel 04:00.'
        return
    }
    $E.TxtAufgabe.Text = 'Wird eingerichtet …'
    try {
        $roh = & $ExePfad -NoProfile -ExecutionPolicy Bypass -File $Kern -AufgabeZeit $zeit 2>&1
        if ($LASTEXITCODE -ne 0) {
            $E.TxtAufgabe.Text = "Hat nicht geklappt: $(($roh | Select-Object -Last 1))"
            return
        }
        # Nicht die eigene Eingabe zurueckspiegeln, sondern neu nachfragen:
        # Angezeigt wird damit, was WIRKLICH eingetragen ist.
        Zeige-Aufgabe (Hole-Aufgabe)
    } catch {
        $E.TxtAufgabe.Text = "Hat nicht geklappt: $($_.Exception.Message)"
    }
})

$E.BtnProtokoll.Add_Click({
    if (-not (Test-Path $LogPfad)) { $E.TxtStatus.Text = 'Noch kein Protokoll vorhanden.'; return }
    if ($AnsichtGeladen) {
        # In der App, schoen gesetzt (Davids Wunsch 08.10.2026).
        Zeige-Details $true 'protokoll'
    } else {
        # Ohne das Ansicht-Modul wie frueher: Kopie im Editor.
        Start-Process -FilePath $ExePfad -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$Kern`"",'-ProtokollAnzeigen')
    }
})
$E.BtnAnsichtVerlauf.Add_Click({ Setze-Ansicht 'verlauf'; Aktualisiere-Kacheln })
$E.BtnAnsichtProtokoll.Add_Click({ Setze-Ansicht 'protokoll'; Aktualisiere-Kacheln })
$E.BtnFilterAlles.Add_Click({ $script:FilterFehler = $false; Zeige-ProtokollAnsicht })
$E.BtnFilterFehler.Add_Click({ $script:FilterFehler = $true; Zeige-ProtokollAnsicht })
# Die vier kleinen Karten oben: Einstellungen, Verlauf und Protokoll schalten ihr
# Feld, die erste zeigt nur das Ergebnis.
$E.KachelEinstellungen.Add_Click({
    $E.PanelEinstellungen.Visibility = if ($E.PanelEinstellungen.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
    Aktualisiere-Kacheln
})
$E.KachelVerlauf.Add_Click({
    if ((Details-Offen) -and $script:AnsichtModus -eq 'verlauf') { Zeige-Details $false } else { Zeige-Details $true 'verlauf' }
})
$E.KachelProtokolle.Add_Click({
    if (-not (Test-Path $LogPfad)) { $E.TxtStatus.Text = 'Noch kein Protokoll vorhanden.'; return }
    if ((Details-Offen) -and $script:AnsichtModus -eq 'protokoll') { Zeige-Details $false } else { Zeige-Details $true 'protokoll' }
})
foreach ($c in @($E.ChkWinget, $E.ChkChoco, $E.ChkWindows, $E.ChkStore, $E.ChkTreiber)) { $c.Add_Click({ Aktualisiere-Kacheln }) }

# Ein Hyperlink in WPF oeffnet von sich aus GAR NICHTS - ohne diesen Handler
# ist er nur blauer Text. Die Adresse steht fest im Fenster, es kommt nichts
# von aussen hinein, deshalb genuegt hier der direkte Aufruf.
$E.LinkMelucio.Add_RequestNavigate({
    param($absender, $ereignis)
    try { Start-Process $ereignis.Uri.AbsoluteUri } catch { }
    $ereignis.Handled = $true
})

$E.BtnSchliessen.Add_Click({ $fenster.Close() })

# Beim Schliessen aufraeumen: Ein Kindprozess, der weiterinstalliert, waehrend
# sein Fenster weg ist, ist genau die Sorte Geist, die man spaeter im
# Task-Manager sucht.
$fenster.Add_Closing({
    $Takt.Stop()
    if ($Lauf.kind -gt 0) {
        try { Stop-Process -Id $Lauf.kind -Force -ErrorAction Stop } catch { }
    }
    Raeume-Lauf-Auf
})

function Hole-Aufgabe {
    <#
        Fragt den Kern nach dem Zustand der Aufgabenplanung.

        NICHT selbst nachsehen, obwohl es hier zwei Zeilen waeren: Ob eine
        Aufgabe "auf diese Fassung zeigt", ist eine Fachfrage (Pfade
        aufloesen, Gross- und Kleinschreibung, Sonderformen), und die gehoert
        genau einmal beantwortet. Dieselbe Regel wie bei den Auftraegen: Die
        Oberflaeche fragt, der Kern weiss.
    #>
    try {
        $roh = & $ExePfad -NoProfile -ExecutionPolicy Bypass -File $Kern -AufgabeStatus 2>&1
        $zeile = ($roh | Where-Object { "$_".TrimStart().StartsWith('{') } | Select-Object -Last 1)
        if (-not $zeile) { return $null }
        return $zeile | ConvertFrom-Json
    } catch { return $null }
}

function Zeige-Aufgabe {
    <# Traegt den Zustand in Feld und Zeile ein. #>
    param($a)
    if (-not $a) {
        $E.TxtAufgabe.Text = 'Der Zustand der Aufgabenplanung ließ sich nicht lesen.'
        return
    }
    if (-not $a.eingerichtet) {
        $E.TxtZeit.Text = '04:00'
        $E.TxtAufgabe.Text = 'Kein nächtlicher Lauf eingerichtet. Uhrzeit setzen und übernehmen.'
        return
    }
    if ($a.zeit) { $E.TxtZeit.Text = $a.zeit }
    $text = "Nächster Lauf: $($a.naechsterLauf)"
    if ($a.letzterLauf) { $text += "  ·  zuletzt $($a.letzterLauf)" }
    if (-not $a.zeigtHierher) {
        # Der wichtigste Fall, deshalb zuerst und im Klartext: Die Aufgabe
        # startet eine ANDERE Datei, der nächtliche Lauf arbeitet also mit
        # einem anderen Stand als dieses Fenster.
        $text = "Achtung: Der nächtliche Lauf startet eine andere Fassung ($($a.pfad)). " +
                "Ein Klick auf Übernehmen hängt ihn auf diese hier um.`n" + $text
    }
    # Die Vorgabe der Aufgabenplanung ist Priorität 7 (niedrig). Unter Last
    # kommt der Lauf dann zu kurz, und seine Zeitgrenzen reißen (03.10.2026).
    # Über PSObject.Properties gefragt: Eine ältere Fassung des Kerns kennt
    # das Feld nicht, und unter StrictMode wirft der direkte Zugriff.
    $prio = $a.PSObject.Properties['prioritaet']
    if ($prio -and $null -ne $prio.Value -and [int]$prio.Value -ge 7) {
        $text += "`nLäuft mit niedriger Priorität ($($prio.Value)). Ein Klick auf Übernehmen stellt auf normal um."
    }
    $E.TxtAufgabe.Text = $text
}

# ---------------------------------------------------------------------------
#  Ergebniskarte (Standardansicht) und Protokoll-Ansicht
# ---------------------------------------------------------------------------
$script:LaufAnzahl = 0
$script:AnsichtModus = 'verlauf'
$script:FilterFehler = $false

function Details-Offen { return ($E.PanelDetails.Visibility -eq 'Visible') }

function Zeige-Details {
    param([bool]$Ja, [string]$Modus = '')
    $E.PanelDetails.Visibility = if ($Ja) { 'Visible' } else { 'Collapsed' }
    if ($Ja) {
        Setze-Ansicht $(if ($Modus) { $Modus } else { $script:AnsichtModus })
        if ($E.Fortschritt.IsIndeterminate) { $E.LiveRahmen.Visibility = 'Visible' }
    } else {
        $E.LiveRahmen.Visibility = 'Collapsed'
    }
    Aktualisiere-Kacheln
}

function Aktualisiere-Kacheln {
    # Zahl der aktiven Quellen und welche Kachel gerade aufgeklappt ist.
    $n = @($E.ChkWinget, $E.ChkChoco, $E.ChkWindows, $E.ChkStore, $E.ChkTreiber | Where-Object { $_.IsChecked }).Count
    $E.TxtKachelEinst.Text = "$n von 5"
    $E.TxtKachelVerlauf.Text = if ($E.Fortschritt.IsIndeterminate) { 'läuft gerade' } else { 'dieser Sitzung' }
    $rahmen = @{
        KachelEinstellungen = ($E.PanelEinstellungen.Visibility -eq 'Visible')
        KachelVerlauf       = ((Details-Offen) -and $script:AnsichtModus -eq 'verlauf')
        KachelProtokolle    = ((Details-Offen) -and $script:AnsichtModus -eq 'protokoll')
    }
    foreach ($k in $rahmen.Keys) {
        # Der Rahmen steckt in der Vorlage; die Stellung zeigt die Hintergrundfarbe.
        if ($rahmen[$k]) { $E[$k].Background = $fenster.FindResource('Tief') }
        else { $E[$k].ClearValue([System.Windows.Controls.Control]::BackgroundProperty) }
    }
}

function Zeige-Ergebnis {
    param([string]$Zahl, [string]$Satz, [string]$Zeit = '', [string]$Ton = 'neutral')
    $schluessel = switch ($Ton) { 'gut' { 'Gut' } 'warn' { 'Warn' } 'schlecht' { 'Schlecht' } default { 'SchriftLei' } }
    $pinsel = $fenster.FindResource($schluessel)
    $E.TxtZahl.Text = $Zahl
    $E.TxtZahl.Foreground = $pinsel
    $glyph = switch ($Ton) { 'gut' { 0xE73E } 'warn' { 0xE7BA } 'schlecht' { 0xE783 } default { 0xE895 } }
    $E.TxtIconErgebnis.Text = [string][char]$glyph
    $E.TxtIconErgebnis.Foreground = $pinsel
    $E.StreifenErgebnis.Background = $pinsel
    $E.TxtErgebnis.Text = $Satz
    $E.TxtErgebnisZeit.Text = $Zeit
    $E.TxtErgebnisZeit.Visibility = if ($Zeit) { 'Visible' } else { 'Collapsed' }
}

# Beim Oeffnen: aus dem Protokoll, was der letzte stille Lauf tat.
function Zeige-LetztenLaufKarte {
    if (-not $AnsichtGeladen) { return }
    try {
        if (-not (Test-Path $LogPfad)) {
            Zeige-Ergebnis -Zahl ([string][char]0x2013) -Satz 'Noch kein Protokoll vorhanden.' -Ton 'neutral'
            return
        }
        $zeilen = Get-Content -Path $LogPfad -Tail 400 -Encoding UTF8 -ErrorAction Stop
        $lauf = Get-LetzterLauf (ConvertTo-ProtokollEintraege $zeilen)
        $karte = Bilde-ErgebnisKarte $lauf
        $zeit = ''
        if ($lauf.Gefunden -and $lauf.Wann -match '^(\d{4})-(\d\d)-(\d\d) (\d\d:\d\d)') {
            $zeit = "Letzter stiller Lauf: $($Matches[3]).$($Matches[2]).$($Matches[1]) um $($Matches[4]) Uhr"
        }
        Zeige-Ergebnis -Zahl $karte.Zahl -Satz $karte.Satz -Zeit $zeit -Ton $karte.Ton
        $n = Get-LaufAnzahl (ConvertTo-ProtokollEintraege $zeilen)
        $E.TxtKachelProto.Text = if ($n -eq 1) { '1 Lauf' } else { "$n Läufe" }
        $E.TxtKachelProtoZeit.Text = if ($lauf.Gefunden -and $lauf.Wann -match '^\d{4}-(\d\d)-(\d\d)') { "zuletzt $($Matches[2]).$($Matches[1])." } else { 'im Protokoll' }
        # Die Kopfzeile sagt dasselbe: nicht doppelt zeigen.
        $E.TxtLetzterLauf.Visibility = 'Collapsed'
    } catch {
        Zeige-Ergebnis -Zahl ([string][char]0x2013) -Satz 'Protokoll konnte nicht gelesen werden.' -Ton 'neutral'
    }
}

# Nach einem Lauf im Fenster: Zahl aus der Ausgabe, sonst Haken oder Ausrufezeichen.
function Zeige-LaufErgebnis {
    param($Schluss, [string]$Art, [int]$Anzahl, [double]$Minuten)
    if ($Schluss.Gut) {
        if ($Art -eq 'pruefen') {
            Zeige-Ergebnis -Zahl ([string][char]0x2713) -Satz 'Nachgesehen. Es wurde nichts verändert.' -Ton 'gut'
        } elseif ($Anzahl -gt 0) {
            $satz = if ($Anzahl -eq 1) { 'Es gab 1 Update, erfolgreich installiert.' } else { "Es gab $Anzahl Updates, alle erfolgreich installiert." }
            Zeige-Ergebnis -Zahl "$Anzahl" -Satz $satz -Zeit "Fertig nach $Minuten Minuten." -Ton 'gut'
        } else {
            Zeige-Ergebnis -Zahl ([string][char]0x2713) -Satz 'Fertig. Nichts war zu aktualisieren oder alles ist durch.' -Zeit "Nach $Minuten Minuten." -Ton 'gut'
        }
    } else {
        Zeige-Ergebnis -Zahl '!' -Satz $Schluss.Status -Zeit 'Einzelheiten unter Details.' -Ton 'schlecht'
    }
}

function Setze-Ansicht {
    param([string]$Modus)
    $script:AnsichtModus = $Modus
    $proto = ($Modus -eq 'protokoll')
    $E.PanelVerlauf.Visibility   = if ($proto) { 'Collapsed' } else { 'Visible' }
    $E.PanelProtokoll.Visibility = if ($proto) { 'Visible' } else { 'Collapsed' }
    $E.BtnFilterAlles.Visibility  = if ($proto) { 'Visible' } else { 'Collapsed' }
    $E.BtnFilterFehler.Visibility = if ($proto) { 'Visible' } else { 'Collapsed' }
    Markiere-Knopf $E.BtnAnsichtVerlauf (-not $proto)
    Markiere-Knopf $E.BtnAnsichtProtokoll $proto
    if ($proto) { Zeige-ProtokollAnsicht }
}

function Markiere-Knopf {
    # Der gewaehlte Knopf der Gruppe steht in der Aktionsfarbe, die anderen leise.
    param($Knopf, [bool]$Aktiv)
    if ($Aktiv) {
        $Knopf.Background = $fenster.FindResource('AkzentKnopf')
        $Knopf.Foreground = [System.Windows.Media.Brushes]::White
    } else {
        $Knopf.ClearValue([System.Windows.Controls.Button]::BackgroundProperty)
        $Knopf.ClearValue([System.Windows.Controls.Button]::ForegroundProperty)
    }
}

function Zeige-ProtokollAnsicht {
    if (-not $AnsichtGeladen -or -not (Test-Path $LogPfad)) {
        $E.TxtStatus.Text = 'Noch kein Protokoll vorhanden.'
        return
    }
    try {
        $zeilen = Get-Content -Path $LogPfad -Tail 2000 -Encoding UTF8 -ErrorAction Stop
        $eintraege = ConvertTo-ProtokollEintraege $zeilen
        $zaehler = Get-ProtokollZaehler $eintraege
        $E.TxtBtnFilterFehler.Text = "Fehler ($($zaehler.Fehler))"
        Markiere-Knopf $E.BtnFilterAlles (-not $script:FilterFehler)
        Markiere-Knopf $E.BtnFilterFehler $script:FilterFehler
        $tage = Gruppiere-ProtokollTage $eintraege -NurFehler:$script:FilterFehler

        $doc = New-Object System.Windows.Documents.FlowDocument
        $doc.PagePadding = New-Object System.Windows.Thickness(8, 4, 8, 4)
        $doc.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $mono = New-Object System.Windows.Media.FontFamily('Cascadia Mono, Consolas')
        $schrift = $fenster.FindResource('Schrift'); $lei = $fenster.FindResource('SchriftLei')
        $farbe = @{ SUCCESS = $fenster.FindResource('Gut'); WARNING = $fenster.FindResource('Warn')
                    ERROR = $fenster.FindResource('Schlecht'); INFO = $lei }
        $fehlerFlaeche = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromArgb(0x22, ($fenster.FindResource('Schlecht')).Color.R,
                ($fenster.FindResource('Schlecht')).Color.G, ($fenster.FindResource('Schlecht')).Color.B))
        if (@($tage).Count -eq 0) {
            $p = New-Object System.Windows.Documents.Paragraph
            $r = New-Object System.Windows.Documents.Run($(if ($script:FilterFehler) { 'Keine Fehler im Protokoll.' } else { 'Das Protokoll ist leer.' }))
            $r.Foreground = $lei; [void]$p.Inlines.Add($r); [void]$doc.Blocks.Add($p)
        }
        foreach ($tag in $tage) {
            $kopf = New-Object System.Windows.Documents.Paragraph
            $kopf.Margin = New-Object System.Windows.Thickness(0, 12, 0, 4)
            $kopf.BorderBrush = $lei
            $kopf.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
            $r = New-Object System.Windows.Documents.Run((Get-TagesKopf $tag.Datum).ToUpper())
            $r.FontSize = 12; $r.FontWeight = 'SemiBold'; $r.Foreground = $lei
            [void]$kopf.Inlines.Add($r); [void]$doc.Blocks.Add($kopf)
            foreach ($ein in $tag.Eintraege) {
                $p = New-Object System.Windows.Documents.Paragraph
                $p.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
                $p.Padding = New-Object System.Windows.Thickness(4, 1, 4, 1)
                if ($ein.Stufe -eq 'ERROR') { $p.Background = $fehlerFlaeche }
                $zeit = New-Object System.Windows.Documents.Run($ein.Zeit)
                $zeit.FontFamily = $mono; $zeit.FontSize = 12; $zeit.Foreground = $lei
                $zeichen = New-Object System.Windows.Documents.Run('  ' + (Get-StufenZeichen $ein.Stufe) + '  ')
                $zeichen.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Symbol')
                $zeichen.Foreground = $farbe[$ein.Stufe]
                $text = New-Object System.Windows.Documents.Run($ein.Text)
                $text.Foreground = $schrift
                [void]$p.Inlines.Add($zeit); [void]$p.Inlines.Add($zeichen); [void]$p.Inlines.Add($text)
                [void]$doc.Blocks.Add($p)
            }
        }
        $E.RtfProtokoll.Document = $doc
    } catch {
        $E.TxtStatus.Text = "Protokoll konnte nicht angezeigt werden: $($_.Exception.Message)"
    }
}

function Lies-LetztenLauf {
    <#
        Was der naechtliche Lauf zuletzt getan hat, in einer Zeile.

        WOFUER (22.09.2026): Der stille Lauf laeuft ohne Fenster. Ob er
        gestern etwas aktualisiert hat, ob er scheiterte oder ob die Aufgabe
        seit Wochen gar nicht mehr startet, steht nur im Protokoll — und wer
        das nicht von sich aus oeffnet, erfaehrt es nie. Dieselbe Sorte
        Stille wie ein Dienst, der gruen aussieht und nichts tut.

        Gelesen wird nur das Ende der Datei: Das Protokoll reicht bis in den
        Maerz zurueck, und die letzten Zeilen genuegen.
    #>
    param([string]$Pfad)
    try {
        if (-not (Test-Path $Pfad)) { return 'Noch kein Protokoll vorhanden.' }
        $zeilen = Get-Content -Path $Pfad -Tail 400 -ErrorAction Stop
        # Auch der GESCHEITERTE Lauf zaehlt als letzter Lauf (03.10.2026): Er
        # schreibt [SILENT-FAILED] statt [SILENT-DONE]. Suchte die Zeile nur
        # nach dem gelungenen, stuende hier nach einer schlechten Nacht der
        # gute Lauf von vorgestern.
        $fertig = $zeilen | Where-Object { $_ -match '\[SILENT-(DONE|FAILED)\]' } | Select-Object -Last 1
        if (-not $fertig) { return 'Noch kein stiller Lauf im Protokoll.' }
        $gescheitert = $fertig -match '\[SILENT-FAILED\]'
        $wann = if ($fertig -match '^\[([\d\-]+) ([\d:]+)\]') { "$($Matches[1]) um $($Matches[2])" } else { 'unbekannt' }

        # Fehler NUR aus dem letzten Lauf, nicht aus der ganzen Datei: Ein
        # Fehler von vor drei Wochen ist keine Aussage ueber heute.
        $ab = [array]::IndexOf($zeilen, ($zeilen | Where-Object { $_ -match 'Silent Mode gestartet' } | Select-Object -Last 1))
        $abschnitt = if ($ab -ge 0) { $zeilen[$ab..($zeilen.Count - 1)] } else { @($fertig) }
        $fehler = @($abschnitt | Where-Object { $_ -match '\[ERROR\]' }).Count
        $getan  = @($abschnitt | Where-Object { $_ -match 'Aktualisiert:' }) | Select-Object -Last 1

        $text = "Letzter stiller Lauf: $wann"
        if ($getan -match 'Aktualisiert:\s*(.+)$') { $text += " — $($Matches[1])" }
        elseif (-not $gescheitert -and ($abschnitt -match 'Keine Updates')) { $text += ' — nichts offen' }
        if ($gescheitert) { $text += ' — gescheitert, wird nachgeholt' }
        if ($fehler -gt 0) { $text += "  ·  $fehler Fehler im Protokoll" }
        return $text
    } catch {
        return 'Protokoll konnte nicht gelesen werden.'
    }
}

# Hardware und Aufgabenplanung beim Oeffnen nachtragen — NEBENHER (22.09.2026).
#
# GEMESSEN, warum: Die Hardware ueber CIM kostet 1,4 s, die Abfrage der
# Aufgabenplanung 3,0 s (eigener Prozess plus `Get-ScheduledTask`, das allein
# 1,7 s braucht). Beides lief bis eben hier, im Faden des Fensters — also
# stand die Oberflaeche nach dem Oeffnen rund viereinhalb Sekunden still,
# bevor man den ersten Schalter umlegen konnte. Das war Davids "laedt
# langsam".
#
# Jetzt laeuft beides in einem eigenen Faden, und die Zeilen fuellen sich,
# wenn die Antwort da ist. Zurueck ins Fenster geht es ueber den Dispatcher:
# Auf ein WPF-Element darf nur sein eigener Faden schreiben.
function Lade-Nebenher {
    $E.TxtLetzterLauf.Text = Lies-LetztenLauf $LogPfad   # liest nur Dateiende, schnell
    $E.TxtAufgabe.Text = 'Aufgabenplanung wird gelesen …'

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Kern', $Kern)
    $rs.SessionStateProxy.SetVariable('ExePfad', $ExePfad)
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        $hardware = try {
            $cpu   = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
            $gpu   = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name
            $board = (Get-CimInstance Win32_BaseBoard).Manufacturer
            "$cpu  ·  $gpu  ·  $board"
        } catch { 'Hardware konnte nicht gelesen werden.' }

        $aufgabe = try {
            $roh = & $ExePfad -NoProfile -ExecutionPolicy Bypass -File $Kern -AufgabeStatus 2>&1
            ($roh | Where-Object { "$_".TrimStart().StartsWith('{') } | Select-Object -Last 1)
        } catch { $null }

        [pscustomobject]@{ Hardware = $hardware; AufgabeJson = $aufgabe }
    })
    $handle = $ps.BeginInvoke()

    # Ein Takt statt eines Rueckrufs: Ein `Add_InvocationStateChanged` liefe im
    # fremden Faden, und von dort aus ans Fenster zu greifen ist genau der
    # Fehler, den dieser Umbau vermeiden soll.
    $warten = New-Object System.Windows.Threading.DispatcherTimer
    $warten.Interval = [TimeSpan]::FromMilliseconds(150)
    $warten.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $warten.Stop()
        try {
            $ergebnis = $ps.EndInvoke($handle) | Select-Object -First 1
            if ($ergebnis) {
                $E.TxtHardware.Text = $ergebnis.Hardware
                $a = if ($ergebnis.AufgabeJson) { $ergebnis.AufgabeJson | ConvertFrom-Json } else { $null }
                Zeige-Aufgabe $a
            }
        } catch {
            $E.TxtHardware.Text = 'Hardware konnte nicht gelesen werden.'
        } finally {
            $ps.Dispose(); $rs.Dispose()
        }
    }.GetNewClosure())
    $warten.Start()
}

# ---------------------------------------------------------------------------
#  Neue Fassung (SELBST-UPDATE.md)
# ---------------------------------------------------------------------------
$script:NeueFassung = $null
$SUStatus = @{ Bestaetigt = $false }

function Zeige-NeueFassung {
    param($Fassung, $Schalter)
    $zustand = Lies-SelbstUpdateZustand $SelbstUpdateZustand
    $aus = if ($zustand -and $zustand.PSObject.Properties['ausgeblendet']) { "$($zustand.ausgeblendet)" } else { '' }
    if ($aus -and $aus -eq $Fassung.Tag) { return }     # "Später" gilt für diese Fassung
    $script:NeueFassung = $Fassung
    $E.TxtNeueFassung.Text = "Version $($Fassung.Version) ist verfügbar."
    $E.LinkNeueFassung.NavigateUri = [uri]$Fassung.Notizen
    $E.BtnNeueFassung.Visibility = if ($Schalter.Installieren) { 'Visible' } else { 'Collapsed' }
    $E.TxtLinkSeite.Visibility   = if ($Schalter.Installieren) { 'Collapsed' } else { 'Visible' }
    $E.ZeileNeueFassung.Visibility = 'Visible'
}

# Hoechstens einmal am Tag bei GitHub fragen; sonst den gemerkten Stand zeigen.
# Die Abfrage laeuft in einem eigenen Faden (wie Lade-Nebenher): Das Fenster
# darf dabei nicht stehen.
function Pruefe-Neue-Fassung {
    if (-not $SelbstUpdateGeladen) { return }
    $schalter = Lies-SelbstUpdateSchalter $SkriptOrdner
    if (-not $schalter.Pruefen) { return }
    $zustand = Lies-SelbstUpdateZustand $SelbstUpdateZustand
    if (Test-HeuteSchonGefragt $zustand) {
        $f = Lies-GemerkteFassung $zustand
        if ($f -and (Test-FassungNeuer $f.Tag $UpdaterVersion)) { Zeige-NeueFassung $f $schalter }
        return
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Modul', $SelbstUpdateDatei)
    $rs.SessionStateProxy.SetVariable('Ist', $UpdaterVersion)
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({ . $Modul; Frage-NeuesteFassung $Ist })
    $handle = $ps.BeginInvoke()
    $warten = New-Object System.Windows.Threading.DispatcherTimer
    $warten.Interval = [TimeSpan]::FromMilliseconds(300)
    $warten.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $warten.Stop()
        try {
            $f = $ps.EndInvoke($handle) | Select-Object -First 1
            if ($f -and -not (Test-FassungNeuer $f.Tag $UpdaterVersion)) { $f = $null }
            $alt = Lies-SelbstUpdateZustand $SelbstUpdateZustand
            $aus = if ($alt -and $alt.PSObject.Properties['ausgeblendet']) { "$($alt.ausgeblendet)" } else { '' }
            Schreibe-SelbstUpdateZustand $SelbstUpdateZustand $f $aus
            if ($f) { Zeige-NeueFassung $f $schalter }
        } catch { } finally { $ps.Dispose(); $rs.Dispose() }
    }.GetNewClosure())
    $warten.Start()
}

$E.BtnFassungSpaeter.Add_Click({
    if ($script:NeueFassung) {
        $z = Lies-SelbstUpdateZustand $SelbstUpdateZustand
        Schreibe-SelbstUpdateZustand $SelbstUpdateZustand (Lies-GemerkteFassung $z) $script:NeueFassung.Tag
    }
    $E.ZeileNeueFassung.Visibility = 'Collapsed'
})

foreach ($l in @($E.LinkNeueFassung, $E.LinkUpdateSeite)) {
    $l.Add_RequestNavigate({
        param($absender, $ereignis)
        # Die Adresse kommt aus Waehle-Fassung (fester Anfang) oder steht fest im Fenster.
        try { Start-Process $ereignis.Uri.AbsoluteUri } catch { }
        $ereignis.Handled = $true
    })
}

# Installieren: zwei Klicks, solange das Setup unsigniert ist (Rueckfrage im
# Fenster, kein Dialog). Laden, Pruefen und Starten laufen in einem eigenen
# Faden; das Fenster schliesst sich erst, wenn das Setup durch ist, und wird
# danach neu geoeffnet.
$E.BtnNeueFassung.Add_Click({
    if (-not $script:NeueFassung -or $Lauf.kind -gt 0) { return }
    # Nicht nur "Knopf unsichtbar": Der Schalter wird hier noch einmal gelesen.
    if (-not (Lies-SelbstUpdateSchalter $SkriptOrdner).Installieren) { return }
    $signiert = [bool]$script:SU_SignaturAussteller
    if (-not $signiert -and -not $SUStatus.Bestaetigt) {
        $SUStatus.Bestaetigt = $true
        $E.TxtNeueFassung.Text = 'Das Setup ist noch nicht signiert; Windows meldet evtl. einen unbekannten Herausgeber. Die Prüfsumme wird vor dem Start geprüft.'
        $E.BtnNeueFassung.Content = 'Ja, installieren'
        return
    }
    $tagNeu = $script:NeueFassung.Tag
    $E.BtnNeueFassung.IsEnabled = $false
    $E.BtnFassungSpaeter.IsEnabled = $false
    $E.TxtNeueFassung.Text = 'Wird geladen und installiert …'
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Modul', $SelbstUpdateDatei)
    $rs.SessionStateProxy.SetVariable('Fassung', $script:NeueFassung)
    $rs.SessionStateProxy.SetVariable('Ordner', $SelbstUpdateOrdner)
    $rs.SessionStateProxy.SetVariable('Unsig', (-not $signiert))
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        . $Modul
        try {
            $d = Lade-Setup $Fassung $Ordner
            Installiere-Setup -Pfad $d.Pfad -ErwarteteSumme $d.Summe -UnsigniertErlaubt:$Unsig
        } catch {
            @{ Gestartet = $false; ExitCode = $null; Meldung = "Nicht geladen: $($_.Exception.Message)" }
        }
    })
    $handle = $ps.BeginInvoke()
    $warten = New-Object System.Windows.Threading.DispatcherTimer
    $warten.Interval = [TimeSpan]::FromMilliseconds(500)
    $warten.Add_Tick({
        if (-not $handle.IsCompleted) { return }
        $warten.Stop()
        $erg = $null
        try { $erg = $ps.EndInvoke($handle) | Select-Object -First 1 } catch { }
        $ps.Dispose(); $rs.Dispose()
        $ok = $erg -and $erg.Gestartet -and $erg.ExitCode -eq 0
        try {
            $zeile = '[{0}] [GUI] [{1}] Selbst-Update auf {2}: {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
                     $(if ($ok) { 'INFO' } else { 'ERROR' }), $tagNeu, $(if ($erg) { $erg.Meldung } else { 'keine Antwort' })
            Add-Content -Path $LogPfad -Value $zeile -Encoding UTF8
        } catch { }
        if ($ok) {
            Start-Process -FilePath (Join-Path $SkriptOrdner 'update-manager-gui.bat') -WorkingDirectory $SkriptOrdner
            $fenster.Close()
            return
        }
        $E.TxtNeueFassung.Text = "Nicht installiert: $(if ($erg) { $erg.Meldung } else { 'keine Antwort' }). Die bisherige Version bleibt."
        $E.BtnNeueFassung.Content = 'Neue Version installieren'
        $SUStatus.Bestaetigt = $false
        $E.BtnNeueFassung.IsEnabled = $true
        $E.BtnFassungSpaeter.IsEnabled = $true
    }.GetNewClosure())
    $warten.Start()
})

$fenster.Add_ContentRendered({ Zeige-LetztenLaufKarte; Aktualisiere-Kacheln; Lade-Nebenher; Pruefe-Neue-Fassung })

if ($Abbild) {
    # NICHT das Fenster zeichnen, sondern seinen INHALT. Ein Window, das nie
    # gezeigt wurde, hat keine gezeichnete Oberflaeche: `Render` liefert dann
    # ein weisses Bild — ohne Fehler, ohne Hinweis (beim ersten Anlauf am
    # 22.09.2026 genau so passiert, zweimal 2292 Byte Nichts).
    #
    # Der Inhalt dagegen laesst sich messen, anordnen und zeichnen wie jedes
    # Steuerelement. Der Hintergrund des Fensters kommt als Rahmen darum,
    # sonst faellt die Flaeche hinter den Karten weg.
    $breite = [int]$fenster.Width
    $hoehe  = [int]$fenster.Height
    $inhalt = $fenster.Content
    $fenster.Content = $null
    $rahmen = New-Object System.Windows.Controls.Border
    $rahmen.Background = $fenster.Background
    $rahmen.Child = $inhalt
    $rahmen.Width = $breite
    $rahmen.Height = $hoehe
    $rahmen.Measure([System.Windows.Size]::new($breite, $hoehe))
    $rahmen.Arrange([System.Windows.Rect]::new(0, 0, $breite, $hoehe))
    $rahmen.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
        $breite, $hoehe, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($rahmen)
    $geber = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $geber.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $strom = [System.IO.File]::Create($Abbild)
    try { $geber.Save($strom) } finally { $strom.Dispose() }
    Write-Host "Abbild geschrieben: $Abbild ($(if ($AppsHell) { 'hell' } else { 'dunkel' }))"
    exit 0
}

if ($Selbsttest) {
    Lade-Nebenher
    $frist = [datetime]::UtcNow.AddSeconds(20)
    while ([datetime]::UtcNow -lt $frist -and
           ($E.TxtHardware.Text -eq 'Hardware wird erkannt …' -or
            $E.TxtAufgabe.Text  -eq 'Aufgabenplanung wird gelesen …')) {
        # Die Nachrichtenschleife von Hand drehen: Ohne ShowDialog laeuft der
        # Dispatcher nicht, und der Takt, der das Ergebnis abholt, kaeme nie.
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 50
    }
    Write-Host "Hardware:  $($E.TxtHardware.Text)"
    Write-Host "Aufgabe:   $($E.TxtAufgabe.Text)"
    Write-Host "Letzter:   $($E.TxtLetzterLauf.Text)"
    $offen = @()
    if ($E.TxtHardware.Text -eq 'Hardware wird erkannt …')     { $offen += 'Hardware' }
    if ($E.TxtAufgabe.Text  -eq 'Aufgabenplanung wird gelesen …') { $offen += 'Aufgabe' }
    if ($offen) { Write-Host "NICHT nachgeladen: $($offen -join ', ')"; exit 1 }
    exit 0
}

if ($NurPruefen) {
    Write-Host "Fenster aufgebaut, alle $($E.Count) Elemente gefunden."
    Write-Host "Erscheinung: $Erscheinung -> $(if ($AppsHell) { 'hell' } else { 'dunkel' })"
    Write-Host "Kern: $Kern"
    exit 0
}

[void]$fenster.ShowDialog()
