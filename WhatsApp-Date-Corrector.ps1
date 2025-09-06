<#
.SYNOPSIS
    Corrects the timestamps of WhatsApp media files based on metadata or filename.

.DESCRIPTION
    The script searches a specified folder and all its subfolders for media files.
    It first checks if a file contains metadata such as "Date taken" (for photos/videos) or "Media created".
    If a valid timestamp is found in the metadata, it is used with preference.
    
    If no metadata is available, the script falls back to the WhatsApp pattern in the filename 
    (e.g., IMG-20240115-WA0001.jpg) to extract the date.
    
    The logic for an update is as follows:
    1. For metadata source: Update if CreationTime or LastWriteTime do not exactly match the metadata timestamp.
    2. For filename source: Update only if the *date part* of CreationTime or LastWriteTime does not match the date from the filename.

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
    The path to the starting folder containing the WhatsApp files.

.PARAMETER DryRun
    If this switch is set to $true (default), no changes will be made. 
    The script will only show which files would be changed.
    Set to $false to apply the changes.

.PARAMETER DebugMetadata
    Lists all metadata properties of the first file found and then exits.
    Used to find the correct index numbers for metadata properties.

.PARAMETER DebugParsing
    In a normal run, shows the raw string values of the metadata date fields 
    before attempting to parse them. Useful if the conversion fails.

.EXAMPLE
    # Starts the debug mode to display the raw date values from metadata.
    .\WhatsApp-Date-Corrector.ps1 -DirectoryPath "D:\WhatsApp Images" -DebugParsing
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath,

    [switch]$DryRun = $true,

    [switch]$DebugMetadata,

    [switch]$DebugParsing
)

# --- Script Logic ---

if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
    Write-Error "The specified directory '$DirectoryPath' does not exist."
    return
}

# --- DEBUG MODE: FIND METADATA INDICES ---
if ($DebugMetadata) {
    Write-Host "--- METADATA DEBUG MODE STARTED ---" -ForegroundColor Magenta
    $firstFile = Get-ChildItem -Path $DirectoryPath -File -Recurse | Select-Object -First 1
    if (-not $firstFile) { Write-Error "No files found in the specified path."; return }

    Write-Host "Analyzing metadata for file: $($firstFile.FullName)`n"
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($firstFile.DirectoryName)
    $fileItem = $folder.ParseName($firstFile.Name)

    Write-Host "Index | Property Name        | Value"
    Write-Host "--------------------------------------------------"
    0..400 | ForEach-Object {
        $propName = $folder.GetDetailsOf($null, $_)
        $propValue = $folder.GetDetailsOf($fileItem, $_)
        if ($propName -and $propValue) {
            Write-Host ("{0,5} | {1,-20} | {2}" -f $_, $propName, $propValue)
        }
    }
    Write-Host "`n--- DEBUG MODE FINISHED ---" -ForegroundColor Magenta
    return
}

# --- NORMAL MODE ---

# Configuration
$regexPattern = '^[A-Za-z]{3}-(\d{4})(\d{2})(\d{2})-WA(\d{4})\..+$'
$baseTime = [timespan]"10:00:00"
$dateTakenIndex = 12      # "Date taken"
$mediaCreatedIndex = 208  # "Media created"
$expectedDateFormat = 'dd.MM.yyyy HH:mm'

if ($DryRun -and !$DebugParsing) {
    Write-Host "--- DRY RUN STARTED ---" -ForegroundColor Yellow
    Write-Host "No files will be changed. Actions are only simulated." -ForegroundColor Yellow
} elseif ($DebugParsing) {
    Write-Host "--- PARSING DEBUG MODE STARTED ---" -ForegroundColor Yellow
} else {
    Write-Host "--- LIVE RUN STARTED ---" -ForegroundColor Red
    Write-Host "WARNING: File timestamps will now be permanently changed." -ForegroundColor Red
}
Write-Host "Recursively searching folder: $DirectoryPath`n"

$shell = New-Object -ComObject Shell.Application
$cachedFolders = @{}

$files = Get-ChildItem -Path $DirectoryPath -File -Recurse

foreach ($file in $files) {
    $newTimestamp = $null
    $updateReason = ""

    # STEP 1: Read metadata
    $parentDir = $file.DirectoryName
    if (-not $cachedFolders.ContainsKey($parentDir)) { $cachedFolders[$parentDir] = $shell.Namespace($parentDir) }
    $folder = $cachedFolders[$parentDir]
    $fileItem = $folder.ParseName($file.Name)

    if ($fileItem) {
        $dateTakenStr = $folder.GetDetailsOf($fileItem, $dateTakenIndex)
        $mediaCreatedStr = $folder.GetDetailsOf($fileItem, $mediaCreatedIndex)

        if ($DebugParsing) {
            if ($dateTakenStr) { Write-Host "DEBUG [$($file.Name)]: Raw value for 'Date taken' ($dateTakenIndex): '$dateTakenStr'" -ForegroundColor Gray }
            if ($mediaCreatedStr) { Write-Host "DEBUG [$($file.Name)]: Raw value for 'Media created' ($mediaCreatedIndex): '$mediaCreatedStr'" -ForegroundColor Gray }
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

        if ($newTimestamp) { $updateReason = "Metadata" }
    }
    
    # STEP 2: Fallback to filename
    if (-not $newTimestamp -and $file.Name -match $regexPattern) {
        $year, $month, $day, $sequenceNumber = $matches[1], $matches[2], $matches[3], [int]$matches[4]
        try {
            $targetDate = Get-Date -Year $year -Month $month -Day $day -Hour 0 -Minute 0 -Second 0 -ErrorAction Stop
            $newTimestamp = $targetDate + $baseTime + ([timespan]::FromMinutes($sequenceNumber))
            $updateReason = "Filename"
        } catch {
            Write-Warning "($($file.FullName)) - Invalid date in filename. Skipping."
            continue
        }
    }

    # STEP 3: Decide action (refined logic)
    if (-not $newTimestamp) { continue }

    $needsUpdate = $false
    if ($updateReason -eq 'Metadata') {
        # With metadata, the time is precise. Update if either CreationTime or LastWriteTime does not match exactly.
        if ($file.CreationTime -ne $newTimestamp -or $file.LastWriteTime -ne $newTimestamp) {
            $needsUpdate = $true
        }
    } else { # $updateReason -eq 'Filename'
        # With the filename, we have a dummy time. Update only if the day is wrong for either timestamp.
        $targetDateStr = $newTimestamp.ToString('yyyy-MM-dd')
        if ($file.CreationTime.ToString('yyyy-MM-dd') -ne $targetDateStr -or $file.LastWriteTime.ToString('yyyy-MM-dd') -ne $targetDateStr) {
            $needsUpdate = $true
        }
    }

    if (-not $needsUpdate) {
        Write-Host "($($file.FullName)) - Correct timestamps found (Source: $updateReason). Skipping." -ForegroundColor Gray
        continue
    }
    
    # STEP 4: Perform action
    $logMessage = "($($file.FullName)) | Source: $updateReason | Current (C/W): $($file.CreationTime.ToString('yyyy-MM-dd HH:mm')) / $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) | New: $($newTimestamp.ToString('yyyy-MM-dd HH:mm'))"
    
    if ($DryRun -or $DebugParsing) {
        Write-Host "[DRY RUN] Would change: $logMessage" -ForegroundColor Cyan
    } else {
        try {
            Set-ItemProperty -Path $file.FullName -Name LastWriteTime -Value $newTimestamp -ErrorAction Stop
            Set-ItemProperty -Path $file.FullName -Name CreationTime -Value $newTimestamp -ErrorAction Stop
            Write-Host "CHANGED: $logMessage" -ForegroundColor Green
        } catch {
            Write-Error "Error while modifying file $($file.FullName): $_"
        }
    }
}

Write-Host "`n--- PROCESSING COMPLETE ---"
