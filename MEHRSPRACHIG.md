# Mehrsprachigkeit (Vorschlag, noch nicht umgebaut)

Stand 28.09.2026. Beschreibt, wie die Texte aus den Skripten in Sprachdateien
`lang/*.json` wandern könnten, mit einem Umschalter im Fenster. **Nichts davon
ist gebaut.**

## Wie es heute ist

| Teil | Sprache | Wie |
|---|---|---|
| Kern `universal-update-manager.ps1` | DE und EN | zwei Hashtabellen `$T = @{ … }` im Skript, rund 240 Schlüssel je Sprache; Auswahl über `(Get-Culture).TwoLetterISOLanguageName` |
| Fenster `update-manager-gui.ps1` | nur DE | rund 30 Texte fest im XAML, dazu Meldungen im Code |
| Linux `linux/update-manager.sh` | DE und EN | Textpaare direkt im Aufruf, nach `LANG` |
| Setup `installer/update-manager.iss` | DE und EN | `[Languages]` und `[CustomMessages]` von Inno Setup |

Die Bausteinprobe (`probe.ps1`, Punkt 4) prüft schon heute, dass jeder
benutzte Schlüssel in **beiden** Tabellen steht.

## Zwei Fehler, die vor dem Umbau behoben gehören

1. **Die Sprache kommt aus dem falschen Wert.** `Get-Culture` ist das
   *Format* (Datum, Zahlen), nicht die *Anzeigesprache*. Wer ein englisches
   Windows mit deutschem Datumsformat hat, bekommt deutsche Texte. Richtig ist
   `Get-UICulture` (bzw. `[CultureInfo]::CurrentUICulture`).
2. **Das Fenster liest das Protokoll über übersetzte Texte.** Die Zeile zum
   letzten nächtlichen Lauf sucht im Protokoll nach `Silent Mode gestartet`,
   `Aktualisiert:` und `Keine Updates`. Auf einem englischen System schreibt
   der Kern `Silent Mode started` und `No updates available`; die Zeile im
   Fenster liest dann falsch oder gar nichts. Abhilfe wie bei
   `[SILENT-DONE]`: sprachneutrale Marken ins Protokoll schreiben
   (`[SILENT-START]`, `[SILENT-UPDATED] <Liste>`, `[SILENT-NONE]`) und nur
   diese auswerten. Das gilt unabhängig vom Umbau und ist der kleinere,
   dringendere Teil.

## Vorschlag

### Dateien

```
lang/
  de.json
  en.json
sprache.ps1        # Laden, Auswahl, Rückfall; von Kern UND Fenster eingebunden
```

Eine Datei je Sprache, flache Schlüssel, dieselben Namen wie heute
(`winget_title`, `task_done`, …). Die Fenstertexte bekommen den Vorsatz
`gui_` (`gui_titel`, `gui_knopf_aktualisieren`). Listen bleiben Listen:

```json
{
  "yes_keys": ["j", "J", "y", "Y"],
  "yes_no_prompt": "(J/N)",
  "gui_knopf_aktualisieren": "Aktualisieren"
}
```

Gespeichert als **UTF-8** (mit oder ohne BOM, gelesen wird ausdrücklich als
UTF-8). Damit entfällt für die Texte das Problem, dass Windows PowerShell 5.1
eine .ps1 ohne BOM als Windows-1252 liest.

### Laden (Windows PowerShell 5.1 kann kein `-AsHashtable`)

```powershell
function Get-Sprachtabelle([string]$Sprache) {
    $ordner = Join-Path $PSScriptRoot 'lang'
    $lade = {
        param($code)
        $pfad = Join-Path $ordner "$code.json"
        if (-not (Test-Path $pfad)) { return @{} }
        $obj = [IO.File]::ReadAllText($pfad, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
        $h
    }
    # Rückfall: fehlt ein Schlüssel in der gewählten Sprache, gilt Englisch,
    # fehlt er auch dort, Deutsch. Nie eine leere Zeichenkette, denn eine
    # leere Meldung verschwindet einfach (siehe probe.ps1, Punkt 4).
    $t = & $lade 'de'
    foreach ($code in @('en', $Sprache) | Select-Object -Unique) {
        $neu = & $lade $code
        foreach ($k in $neu.Keys) { $t[$k] = $neu[$k] }
    }
    $t
}
```

### Welche Sprache

In dieser Reihenfolge, die erste gewinnt:

1. Parameter `-Sprache de|en` (das Fenster gibt ihn an jeden Kern-Aufruf
   weiter, damit Fenster und Ausgabe übereinstimmen),
2. `"sprache": "de"` in `update-config.local.json` (dort merkt sich das
   Fenster die Wahl; kein neuer Speicherort),
3. `Get-UICulture`, wenn es dafür eine Datei gibt,
4. sonst Englisch.

### Fenster

- Das XAML trägt statt fester Texte Platzhalter, genau wie heute schon die
  Farben (`__GRUND__`): `Content="__T_gui_knopf_aktualisieren__"`. Vor
  `XamlReader::Parse` werden sie ersetzt, **XML-maskiert** (`&`, `<`, `"`).
  Die vorhandene Prüfung „kein `__…__` mehr übrig“ fängt vergessene
  Schlüssel gleich mit.
- **Umschalter**: rechts oben im Kopf ein kleiner Pillenknopf „EN“ bzw. „DE“
  (zeigt die andere Sprache, wie bei den Websites). Ein Klick speichert die
  Wahl in `update-config.local.json` und baut das Fenster neu auf. Neu
  aufbauen statt Texte einzeln tauschen: Viele Textblöcke haben keinen
  `x:Name`, und ein Tausch, der drei davon vergisst, fällt erst beim Lesen
  auf. Während ein Auftrag läuft, ist der Knopf gesperrt.
- Meldungen im Code (`$E.TxtAufgabe.Text = '…'`) laufen über dieselbe
  Tabelle.

### Probe

`probe.ps1`, Punkt 4 wird umgestellt: Jeder im Kern und im Fenster benutzte
Schlüssel (`$T['…']`, `__T_…__`) muss in **jeder** Datei unter `lang/` stehen,
und keine Datei darf Schlüssel haben, die niemand benutzt. Dazu ein Blick auf
Platzhalter wie `{0}`: gleiche Anzahl in allen Sprachen.

### Weitere Sprachen

Eine neue Datei `lang/xx.json` genügt; fehlende Schlüssel fallen auf Englisch
zurück, und die Probe zeigt, welche es sind. Beiträge dafür sind im
öffentlichen Repo willkommen.

## Aufwand und Reihenfolge

1. Protokoll-Marken sprachneutral machen, `Get-UICulture` (klein, sofort
   sinnvoll).
2. Kern: Tabellen nach `lang/de.json` und `lang/en.json` ziehen, `sprache.ps1`
   einbinden, Probe umstellen. Die Texte selbst ändern sich dabei nicht; der
   Diff muss sich mechanisch nachprüfen lassen.
3. Fenster: Platzhalter, englische Texte, Umschalter.

Jeder Schritt einzeln auf Windows prüfen (Probe, dann einmal von Hand in
beiden Sprachen).
