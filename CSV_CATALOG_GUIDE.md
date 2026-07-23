# Managing the catalog with CSV

The CSV flow is a **round-trip**: export the current catalog → edit the pricing/status columns in Excel → re-import. Both endpoints require a staff login (JWT).

> **Important:** the importer **updates existing products only**, matched by `ASIN` (and `ID` if present). It does **not create** new products — those come from the scraper (Rainforest → `manage_collection`). Rows whose ASIN isn't in the database are reported as "not found" and skipped.

---

## The columns

`catalog_template.csv` has the full set of columns the export produces. Only **five** of them do anything on import — the rest are informational (safe to keep for reference, ignored on upload):

| Column (CSV header)            | Used on import? | Notes                                              |
|--------------------------------|-----------------|----------------------------------------------------|
| `ASIN`                         | Yes (match key) | Required. Identifies the product to update.        |
| `ID`                           | Optional match  | If present, must match the product's ID + ASIN.    |
| `Precio USD`                   | **Yes**         | Sets `price`. Decimal (`.` or `,` both accepted).  |
| `Precio con descuento USD`     | **Yes**         | Sets `price_with_discount`. Leave blank for none.  |
| `Turns`                        | **Yes**         | Markup multiplier (default 3.5).                   |
| `Factor decimal`               | **Yes**         | Pricing factor (default 0.75).                     |
| `Estatus`                      | **Yes**         | `Activo`/`Desactivado` (or `active`/`inactive`).   |
| Título, Marca, Color, …        | No              | Reference only; changing them here has no effect.  |

Editing `Precio USD`, `Turns`, or `Factor decimal` automatically **recalculates each product's `min_weekly_payment`** on import.

---

## Step 1 — Export the current catalog

First log in as admin to get a JWT (returned in the `Authorization` response header):

```powershell
curl -i -X POST "http://localhost:3000/api/login" ^
  -H "Content-Type: application/json" ^
  -d "{\"user\":{\"email\":\"admin@test.com\",\"password\":\"admin123\"}}"
```

Copy the `Authorization: Bearer eyJ...` value from the response. Then export:

```powershell
curl -H "Authorization: Bearer PASTE_TOKEN_HERE" ^
  "http://localhost:3000/api/products/download_csv" -o catalog_export.csv
```

You now have `catalog_export.csv` with every product. (If the catalog is empty, use `catalog_template.csv` as a starting shape.)

## Step 2 — Edit in Excel

Open the CSV in Excel. It's saved UTF-8 with a BOM, so accents (á, ñ) display correctly. Change only the pricing/status columns:
- Adjust `Precio USD` and/or `Precio con descuento USD`.
- Tune `Turns` / `Factor decimal` to reprice a product's weekly payments.
- Set `Estatus` to `Desactivado` to pull an item from the catalog without deleting it.

Save as CSV (keep UTF-8).

## Step 3 — Import the changes

```powershell
curl -X POST "http://localhost:3000/api/products/update_csv" ^
  -H "Authorization: Bearer PASTE_TOKEN_HERE" ^
  -F "file=@catalog_export.csv"
```

The response returns a `job_id` — the file is processed in the background (Sidekiq). Check progress:

```powershell
curl -H "Authorization: Bearer PASTE_TOKEN_HERE" ^
  "http://localhost:3000/api/products/track_csv_job/PASTE_JOB_ID_HERE"
```

The result reports counts: `updated`, `not_found`, `skipped`, and any per-row `errors`.

---

## Quick reference

- Export: `GET /api/products/download_csv`
- Import: `POST /api/products/update_csv` (multipart field `file`)
- Track: `GET /api/products/track_csv_job/:job_id`
- Filename produced by export: `catalogo_productos_YYYYMMDD.csv`
- Status words accepted on import: `Activo`, `Desactivado`, `active`, `inactive`.

`catalog_template.csv` (in this folder) is a filled-in example you can open in Excel right now to see the exact format.
