# dev/ — local demo tooling

Helper files for demoing the app locally. Nothing here is loaded by Rails or used in production — it's safe to keep or delete.

| File                             | What it is                                                                 |
|----------------------------------|----------------------------------------------------------------------------|
| `sample_rainforest_payload.json` | Three fake "scraped" products in the exact shape Rainforest sends.         |
| `generate_catalog.ps1`           | Windows script: seeds an exchange rate, POSTs the payload, lists the result.|
| `generate_catalog.sh`            | Same thing for WSL / macOS / Linux.                                        |

## What it does

The real catalog is built by the **Rainforest scraper**, which POSTs Amazon product
data to `POST /api/products/manage_collection`. That endpoint hands the payload to a
background job (`ProcessProductsJob`) which creates/updates products, categories,
specifications, and images, and converts prices from MXN to USD.

This script **plays the role of the scraper** — no Rainforest account or public URL
needed — so you can watch products actually get created locally.

## How to run

1. Start the app (from the project root):
   ```
   docker compose up
   ```
2. In a second terminal, run the generator:
   - **Windows:** `powershell -File dev\generate_catalog.ps1`
   - **WSL/Mac:** `bash dev/generate_catalog.sh`

You'll see three products listed back. They map to:

| Product                        | Scraped price | Converts to (rate 18) |
|--------------------------------|---------------|-----------------------|
| Sofá seccional 3 plazas        | 5,400 MXN     | $300.00               |
| Refrigerador 18 pies           | 16,200 MXN    | $900.00               |
| Televisor 55" 4K               | 9,000 MXN     | $500.00               |

Watch the background jobs run at http://localhost:3000/sidekiq (user `admin`, password `password`).

## Notes

- **Exchange rate is required.** `ProcessProductsJob` rejects everything if no
  `ExchangeRate` exists, so the script seeds one (USD→MXN = 18) on first run.
- **Full-sync behavior.** Each run *deactivates* any product whose ASIN isn't in the
  payload — mirroring how a real scraper run replaces the live catalog.
- **Images.** The job tries to download the image URLs in the payload. The demo URLs
  are placeholders, so image download may log a failure — that does **not** stop the
  products from being created. Swap in real Amazon image URLs to see images attach.
- **To reprice/toggle** these products afterward, use the CSV flow in
  `../CSV_CATALOG_GUIDE.md`.
