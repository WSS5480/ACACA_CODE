# Generates a demo catalog locally (Windows / PowerShell).
# Simulates the Rainforest scraper by POSTing a sample payload to the app's
# /api/products/manage_collection webhook. Run the app first: `docker compose up`.
#
# Usage:  right-click > Run with PowerShell, or:  powershell -File dev\generate_catalog.ps1

$ErrorActionPreference = "Stop"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
$payload  = Join-Path $here "sample_rainforest_payload.json"

# docker compose must run from the project root (where docker-compose.yml lives).
Push-Location $repoRoot
try {
    Write-Host "1/3  Seeding an exchange rate (USD -> MXN = 18) if none exists..." -ForegroundColor Cyan
    docker compose exec -T web bin/rails runner "ExchangeRate.create!(usd_to_mxn: 18) if ExchangeRate.current_rate <= 0; puts %(   current rate = #{ExchangeRate.current_rate})"

    Write-Host "2/3  Posting scraped-product payload to /api/products/manage_collection..." -ForegroundColor Cyan
    curl.exe -s -X POST "http://localhost:3000/api/products/manage_collection" -H "Content-Type: application/json" --data-binary "@$payload"
    Write-Host ""

    Write-Host "3/3  Waiting for the background job to run, then listing the catalog..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    curl.exe -s "http://localhost:3000/api/products?per_page=50"
    Write-Host ""
    Write-Host "Done. If you see the 3 products above, the scraper pipeline worked." -ForegroundColor Green
    Write-Host "Tip: watch the jobs at http://localhost:3000/sidekiq (admin / password)."
}
finally {
    Pop-Location
}
