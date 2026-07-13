# Download Firefox ARM64 tarball for Orange Pi kiosk
# Save this to the repo root, then SCP to the Orange Pi

$url = "https://ftp.mozilla.org/pub/firefox/releases/latest/linux-aarch64/en-US/firefox-latest.tar.bz2"
$out = Join-Path $PSScriptRoot "firefox-latest.tar.bz2"

Write-Host "Downloading Firefox for Linux ARM64..." -ForegroundColor Green
Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing

Write-Host "Saved to: $out" -ForegroundColor Green
Write-Host "Size: $((Get-Item $out).Length / 1MB) MB" -ForegroundColor Green
