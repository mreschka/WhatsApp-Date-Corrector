<#
.SYNOPSIS
    Korrigiert die Zeitstempel von WhatsApp-Mediendateien basierend auf dem Dateinamen oder Metadaten.

.DESCRIPTION
    Das Skript durchsucht einen angegebenen Ordner und alle seine Unterordner nach Mediendateien.
    Es prüft zuerst, ob eine Datei Metadaten wie "Aufnahmedatum" (für Fotos/Videos) oder "Medium erstellt" enthält.
    Wenn ein gültiger Zeitstempel in den Metadaten gefunden wird, wird dieser bevorzugt verwendet.
    
    Wenn keine Metadaten vorhanden sind, greift das Skript auf das WhatsApp-Muster im Dateinamen 
    (z.B. IMG-20240115-WA0001.jpg) zurück, um das Datum zu extrahieren.
    
    Die Logik für eine Aktualisierung ist wie folgt:
    1. Bei Metadaten-Quelle: Update, wenn CreationTime oder LastWriteTime nicht exakt mit dem Metadaten-Zeitstempel übereinstimmen.
    2. Bei Dateinamen-Quelle: Update nur, wenn der *Datumsteil* von CreationTime oder LastWriteTime nicht mit dem Datum aus dem Dateinamen übereinstimmt.

.LICENSE
    MIT License
    
    Copyright (c) 2024 Gemini
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

.PARAMETER DirectoryPath
    Der Pfad zum Startordner, der die WhatsApp-Dateien enthält.

.PARAMETER DryRun
    Wenn dieser Schalter auf $true gesetzt ist (Standard), werden keine Änderungen 
    vorgenommen. Das Skript zeigt nur an, welche Dateien geändert würden.
    Setzen Sie den Wert auf $false, um die Änderungen tatsächlich durchzuführen.

.PARAMETER DebugMetadata
    Listet alle Metadaten-Eigenschaften der ersten gefundenen Datei auf und beendet sich.
    Dient zum Finden der korrekten Index-Nummern für Metadaten.

.PARAMETER DebugParsing
    Zeigt im normalen Lauf die rohen Zeichenketten der Metadaten-Datumsfelder an,
    bevor versucht wird, sie zu parsen. Nützlich, wenn die Konvertierung fehlschlägt.

.EXAMPLE
    # Startet den Debug-Modus, um die Roh-Datumswerte aus den Metadaten anzuzeigen.
    .\Korrektur-WhatsApp-Datum.ps1 -DirectoryPath "D:\WhatsApp Images" -DebugParsing
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath,

    [switch]$DryRun = $true,

    [switch]$DebugMetadata,

    [switch]$DebugParsing
)

# --- Skript-Logik ---

if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
    Write-Error "Das angegebene Verzeichnis '$DirectoryPath' existiert nicht."
    return
}

# --- DEBUG-MODUS: METADATEN-INDIZES FINDEN ---
if ($DebugMetadata) {
    Write-Host "--- DEBUG-MODUS FÜR METADATEN GESTARTET ---" -ForegroundColor Magenta
    $firstFile = Get-ChildItem -Path $DirectoryPath -File -Recurse | Select-Object -First 1
    if (-not $firstFile) { Write-Error "Keine Dateien im angegebenen Pfad gefunden."; return }

    Write-Host "Analysiere Metadaten für die Datei: $($firstFile.FullName)`n"
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($firstFile.DirectoryName)
    $fileItem = $folder.ParseName($firstFile.Name)

    Write-Host "Index | Eigenschaftsname       | Wert"
    Write-Host "--------------------------------------------------"
    0..400 | ForEach-Object {
        $propName = $folder.GetDetailsOf($null, $_)
        $propValue = $folder.GetDetailsOf($fileItem, $_)
        if ($propName -and $propValue) {
            Write-Host ("{0,5} | {1,-20} | {2}" -f $_, $propName, $propValue)
        }
    }
    Write-Host "`n--- DEBUG-MODUS BEENDET ---" -ForegroundColor Magenta
    return
}

# --- NORMALER MODUS ---

# Konfiguration
$regexPattern = '^[A-Za-z]{3}-(\d{4})(\d{2})(\d{2})-WA(\d{4})\..+$'
$baseTime = [timespan]"10:00:00"
$dateTakenIndex = 12      # "Aufnahmedatum"
$mediaCreatedIndex = 208  # "Medium erstellt"
$expectedDateFormat = 'dd.MM.yyyy HH:mm'

if ($DryRun -and !$DebugParsing) {
    Write-Host "--- TESTLAUF (DRY RUN) GESTARTET ---" -ForegroundColor Yellow
    Write-Host "Es werden keine Dateien geändert. Die Aktionen werden nur simuliert." -ForegroundColor Yellow
} elseif ($DebugParsing) {
    Write-Host "--- PARSING-DEBUG-MODUS GESTARTET ---" -ForegroundColor Yellow
} else {
    Write-Host "--- ECHTLAUF GESTARTET ---" -ForegroundColor Red
    Write-Host "WARNUNG: Die Zeitstempel der Dateien werden jetzt dauerhaft geändert." -ForegroundColor Red
}
Write-Host "Durchsuche rekursiv Ordner: $DirectoryPath`n"

$shell = New-Object -ComObject Shell.Application
$cachedFolders = @{}

$files = Get-ChildItem -Path $DirectoryPath -File -Recurse

foreach ($file in $files) {
    $newTimestamp = $null
    $updateReason = ""

    # SCHRITT 1: Metadaten lesen
    $parentDir = $file.DirectoryName
    if (-not $cachedFolders.ContainsKey($parentDir)) { $cachedFolders[$parentDir] = $shell.Namespace($parentDir) }
    $folder = $cachedFolders[$parentDir]
    $fileItem = $folder.ParseName($file.Name)

    if ($fileItem) {
        $dateTakenStr = $folder.GetDetailsOf($fileItem, $dateTakenIndex)
        $mediaCreatedStr = $folder.GetDetailsOf($fileItem, $mediaCreatedIndex)

        if ($DebugParsing) {
            if ($dateTakenStr) { Write-Host "DEBUG [$($file.Name)]: Rohwert für 'Aufnahmedatum' ($dateTakenIndex): '$dateTakenStr'" -ForegroundColor Gray }
            if ($mediaCreatedStr) { Write-Host "DEBUG [$($file.Name)]: Rohwert für 'Medium erstellt' ($mediaCreatedIndex): '$mediaCreatedStr'" -ForegroundColor Gray }
        }
        
        function Parse-MetadataDate($rawString, $format) {
            if (-not [string]::IsNullOrWhiteSpace($rawString)) {
                $cleanedString = $rawString -replace '[^\d\s\.:]'
                try { return [datetime]::ParseExact($cleanedString, $format, $null) } catch { return $null }
            }
            return $null
        }

        $newTimestamp = Parse-MetadataDate -rawString $dateTakenStr -format $expectedDateFormat
        if (-not $newTimestamp) { $newTimestamp = Parse-MetadataDate -rawString $mediaCreatedStr -format $expectedDateFormat }

        if ($newTimestamp) { $updateReason = "Metadaten" }
    }
    
    # SCHRITT 2: Fallback auf Dateinamen
    if (-not $newTimestamp -and $file.Name -match $regexPattern) {
        $year, $month, $day, $sequenceNumber = $matches[1], $matches[2], $matches[3], [int]$matches[4]
        try {
            $targetDate = Get-Date -Year $year -Month $month -Day $day -Hour 0 -Minute 0 -Second 0 -ErrorAction Stop
            $newTimestamp = $targetDate + $baseTime + ([timespan]::FromMinutes($sequenceNumber))
            $updateReason = "Dateiname"
        } catch {
            Write-Warning "($($file.FullName)) - Ungültiges Datum im Namen. Wird übersprungen."
            continue
        }
    }

    # SCHRITT 3: Aktion entscheiden (verfeinerte Logik)
    if (-not $newTimestamp) { continue }

    $needsUpdate = $false
    if ($updateReason -eq 'Metadaten') {
        # Bei Metadaten ist die Uhrzeit präzise. Update, wenn entweder CreationTime oder LastWriteTime nicht exakt übereinstimmt.
        if ($file.CreationTime -ne $newTimestamp -or $file.LastWriteTime -ne $newTimestamp) {
            $needsUpdate = $true
        }
    } else { # $updateReason -eq 'Dateiname'
        # Beim Dateinamen haben wir eine Dummy-Uhrzeit. Update nur, wenn der Tag bei einem der beiden Zeitstempel falsch ist.
        $targetDateStr = $newTimestamp.ToString('yyyy-MM-dd')
        if ($file.CreationTime.ToString('yyyy-MM-dd') -ne $targetDateStr -or $file.LastWriteTime.ToString('yyyy-MM-dd') -ne $targetDateStr) {
            $needsUpdate = $true
        }
    }

    if (-not $needsUpdate) {
        Write-Host "($($file.FullName)) - Korrekte Zeitstempel gefunden (Quelle: $updateReason). Wird übersprungen." -ForegroundColor Gray
        continue
    }
    
    # SCHRITT 4: Aktion durchführen
    $logMessage = "($($file.FullName)) | Quelle: $updateReason | Aktuell (C/W): $($file.CreationTime.ToString('yyyy-MM-dd HH:mm')) / $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) | Neu: $($newTimestamp.ToString('yyyy-MM-dd HH:mm'))"
    
    if ($DryRun -or $DebugParsing) {
        Write-Host "[TEST] Würde ändern: $logMessage" -ForegroundColor Cyan
    } else {
        try {
            Set-ItemProperty -Path $file.FullName -Name LastWriteTime -Value $newTimestamp -ErrorAction Stop
            Set-ItemProperty -Path $file.FullName -Name CreationTime -Value $newTimestamp -ErrorAction Stop
            Write-Host "GEÄNDERT: $logMessage" -ForegroundColor Green
        } catch {
            Write-Error "Fehler beim Ändern der Datei $($file.FullName): $_"
        }
    }
}

Write-Host "`n--- VERARBEITUNG ABGESCHLOSSEN ---"


