#!/usr/bin/env bash
# Generates a demo catalog locally (WSL / macOS / Linux).
# Simulates the Rainforest scraper by POSTing a sample payload to the app's
# /api/products/manage_collection webhook. Run the app first: `docker compose up`.
#
# Usage:  bash dev/generate_catalog.sh

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$DIR")"
cd "$REPO_ROOT"  # docker compose must run from the project root

echo "1/3  Seeding an exchange rate (USD -> MXN = 18) if none exists..."
docker compose exec -T web bin/rails runner \
  "ExchangeRate.create!(usd_to_mxn: 18) if ExchangeRate.current_rate <= 0; puts \"   current rate = #{ExchangeRate.current_rate}\""

echo "2/3  Posting scraped-product payload to /api/products/manage_collection..."
curl -s -X POST "http://localhost:3000/api/products/manage_collection" \
  -H "Content-Type: application/json" \
  --data-binary "@$DIR/sample_rainforest_payload.json"
echo

echo "3/3  Waiting for the background job to run, then listing the catalog..."
sleep 5
curl -s "http://localhost:3000/api/products?per_page=50"
echo
echo "Done. If you see the 3 products above, the scraper pipeline worked."
echo "Tip: watch the jobs at http://localhost:3000/sidekiq (admin / password)."
