# Ácasa API

Backend API for Ácasa, a cross-border buy-now-pay-later platform. US-based clients
purchase products (Amazon items, tracked by ASIN) on weekly-installment credit, with
delivery to a **beneficiary** in Mexico. The API handles the product catalog, credit
pricing, orders, and the people attached to each order (buyer, guarantor, referrals).

## Stack

- Ruby 3.3.2, Rails 7.1 (API-only)
- PostgreSQL
- Redis + Sidekiq (background jobs) with sidekiq-scheduler (cron jobs)
- Devise + devise-jwt (authentication)
- Active Storage (product images; local disk in dev, S3 in production)
- Rainforest API webhook for catalog ingestion

## Quick start (Docker — recommended on Windows)

```bash
docker compose up --build
```

The API comes up at http://localhost:3000, Sidekiq UI at http://localhost:3000/sidekiq.
On first boot the database is created, migrated, and seeded automatically.

Full walkthrough, including a native (non-Docker) setup, is in **RUN_LOCALLY.md**.

### Seeded test accounts

| Role   | Login                              | Password      |
|--------|------------------------------------|---------------|
| Client | `cliente@test.com` / number `123456` | `password123` |
| Admin  | `admin@test.com`                   | `admin123`    |

## Running the tests

The suite uses RSpec. After `bundle install`:

```bash
bin/rails db:test:prepare
bundle exec rspec
```

With Docker:

```bash
docker compose exec web bundle exec rspec
```

Covered so far: the pricing engine (`Product#calculate_weekly_payment`), the payment-plan
simulator endpoint, `ExchangeRate`, and the exchange-rate fetch job.

## Key endpoints

| Method | Path                                  | Auth        | Purpose                                  |
|--------|---------------------------------------|-------------|------------------------------------------|
| POST   | `/api/login`, `/api/signup`           | none        | Auth (JWT returned in `Authorization`)   |
| GET    | `/api/orders/simulate_payment_plans`  | none        | Weekly-payment plans for a product       |
| GET/POST | `/api/orders`                       | client/JWT  | List / create orders                     |
| GET    | `/api/orders/dashboard`               | JWT         | Client / prequalification / order counts |
| GET/POST | `/api/products`                     | JWT (writes)| Catalog                                  |
| POST   | `/api/products/manage_collection`     | none (webhook) | Rainforest scraper ingestion          |
| GET/POST | `/api/products/download_csv` / `update_csv` | JWT   | CSV catalog export / bulk update         |
| GET/POST/DELETE | `/api/exchange_rates`        | JWT         | USD→MXN rates                            |

Pricing lives in `app/models/product.rb#calculate_weekly_payment`. See **CSV_CATALOG_GUIDE.md**
for catalog maintenance and **dev/** for a local scraper simulation.

## Scheduled jobs

`ExchangeRates::FetchRateJob` runs daily (see `config/sidekiq_schedule.yml`), fetching the
USD→MXN rate and storing a new `ExchangeRate` when it changes. It requires a running Sidekiq
server. The API source URL is configurable via `EXCHANGE_RATE_API_URL` (defaults to a no-key
provider).

## Environment variables

| Variable | Used for | Notes |
|----------|----------|-------|
| `DATABASE_URL` | Postgres connection | Set by Docker; required for a native run |
| `REDIS_URL` | Sidekiq | Defaults to `redis://localhost:6379/1` |
| `SIDEKIQ_USERNAME` / `SIDEKIQ_PASSWORD` | Sidekiq web UI auth | **Required in production** — the UI is disabled if unset (no default admin/password) |
| `EXCHANGE_RATE_API_URL` | Exchange-rate job | Optional |
| `ALLOWED_ORIGINS` | CORS | Comma-separated; dev default set in code |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` / `AWS_S3_BUCKET` | Active Storage (S3) | Falls back to local disk if unset |
| `DEVISE_JWT_SECRET_KEY` | JWT signing | Defaults to `secret_key_base` |

## Deployment

The API deploys to **Hatchbox** (not Vercel — Vercel hosts the separate frontend). See
**DEPLOYMENT.md** for the Bundler/Hatchbox specifics. After changing the `Gemfile`, run
`bundle install` and commit the updated `Gemfile.lock` before deploying.

## Project layout

```
app/
  controllers/api/   REST controllers
  models/            Product (pricing), Order, User, ExchangeRate, ...
  services/          CSV import/export, zip-code population
  sidekiq/           Background jobs (mailing, catalog ingestion, exchange rate)
config/
  routes.rb          API routes + Sidekiq UI mount
  sidekiq_schedule.yml  Cron schedule
spec/                RSpec tests
dev/                 Local demo tooling (not loaded by Rails)
```
