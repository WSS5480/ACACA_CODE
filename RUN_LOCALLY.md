# Running the Ácasa API locally (Windows)

This backend is a Rails 7.1 API. It needs three things to run: **Ruby 3.3.2**, **PostgreSQL**, and **Redis**.
On Windows the easiest, most reliable way to get all three is **Docker** — you install one program and run one command. A native (no-Docker) path is at the bottom if you prefer.

---

## Option A — Docker (recommended)

### 1. Install Docker Desktop
Download and install Docker Desktop for Windows: https://www.docker.com/products/docker-desktop/
When it finishes, launch it and wait until it says **"Engine running"** (bottom-left is green). Leave it open.

### 2. Open a terminal in this folder
Open **PowerShell**, then move into this project folder:
```powershell
cd "$env:USERPROFILE\OneDrive\Desktop\acasa-api-main"
```

### 3. Start everything (one command)
```powershell
docker compose up --build
```
The first run takes a few minutes (it downloads Ruby/Postgres/Redis and installs the app's gems). It's ready when you see a line like:
```
Puma ... Listening on http://0.0.0.0:3000
```
Leave this window running. To stop later: press **Ctrl+C**, or in another window run `docker compose down`.

That single command starts four pieces: the **API** (port 3000), **PostgreSQL**, **Redis**, and a **Sidekiq** background worker. On first boot it also creates the database, loads the schema, and seeds test data automatically.

### 4. Try it
The database is pre-seeded (see credentials below). Quick checks:

**Health check** — open in a browser: http://localhost:3000/up (should show green / 200).

**Payment-plan simulator** (public, no login needed). This is the core pricing feature — it returns weekly payments for 4 terms (52/34/26/13 weeks). You need a product first; the seed doesn't create products, so create one from a terminal:
```powershell
docker compose exec web bin/rails runner "Product.create!(title: 'Demo Sofa', asin: 'DEMO12345', price: 300, turns: 3.5, decimal_factor: 0.75)"
```
Then call the simulator (note `product_price` must equal the product's price, and `downpayment + used_credit` must equal it too):
```powershell
curl "http://localhost:3000/api/orders/simulate_payment_plans?product_id=1&product_price=300&downpayment=300&used_credit=0"
```
You'll get back the four plans with their weekly payments.

**Log in as a client** (returns a JWT in the `Authorization` response header):
```powershell
curl -i -X POST "http://localhost:3000/api/login" -H "Content-Type: application/json" -d "{\"user\":{\"email\":\"cliente@test.com\",\"password\":\"password123\"}}"
```

**Sidekiq dashboard** (background jobs / emails): http://localhost:3000/sidekiq — user `admin`, password `password`.

### Seeded test credentials
| Role   | Login                          | Password      | Notes                         |
|--------|--------------------------------|---------------|-------------------------------|
| Client | `cliente@test.com` / no. `123456` | `password123` | Has $500 store credit         |
| Admin  | `admin@test.com`               | `admin123`    | Staff/JWT access              |

### Handy Docker commands
```powershell
docker compose up            # start (after first build)
docker compose down          # stop and remove containers
docker compose down -v       # stop AND wipe the database (fresh start)
docker compose exec web bin/rails console   # open a Rails console
docker compose exec web bin/rails db:seed   # re-run the seed data
docker compose logs -f web   # follow the API logs
```

---

## What this app does (quick orientation for the demo)

Ácasa is a cross-border **buy-now-pay-later** platform. A US-based client buys a product (Amazon items, tracked by ASIN) on a weekly-payment credit plan, delivered to a **beneficiary** in Mexico. Key flows to show in a demo:

1. **Simulate payment plans** — `GET /api/orders/simulate_payment_plans` → four weekly-payment options. Pure pricing math, no login. *Best opening demo.*
2. **Client signup / login** — `POST /api/signup`, `POST /api/login` (JWT).
3. **Create an order** — `POST /api/orders` — validates the client's credit, computes the weekly payment, and deducts used credit.
4. **Attach people to an order** — beneficiaries, guarantor (aval), referrals.
5. **Admin dashboard** — `GET /api/orders/dashboard` — counts of clients, prequalifications, and orders.
6. **Product catalog import** — CSV upload → background jobs pull product data and images.

Pricing lives in `app/models/product.rb#calculate_weekly_payment`: `financed = price × turns − downpayment − (price − used_credit)`, spread across the weeks, plus a 10% "waiver". Defaults: `turns = 3.5`, `decimal_factor = 0.75`.

---

## Option B — Native (no Docker)

Only if you'd rather not use Docker. More moving parts on Windows.

1. **Ruby 3.3.2** — install via [RubyInstaller for Windows](https://rubyinstaller.org/) (pick 3.3.2 **with DevKit**), or use WSL2 + rbenv.
2. **PostgreSQL** — install from https://www.postgresql.org/download/windows/ and remember the `postgres` password you set.
3. **Redis** — Windows has no official Redis; use **WSL2** (`sudo apt install redis-server`) or [Memurai](https://www.memurai.com/) (Redis-compatible for Windows).
4. In this folder:
   ```powershell
   copy .env.example .env
   ```
   Edit `.env` so `DATABASE_URL` matches your Postgres user/password.
5. Install gems and prepare the database:
   ```powershell
   gem install bundler -v 2.7.1
   bundle install
   bin/rails db:prepare
   ```
6. Start the API and (in a second terminal) the worker:
   ```powershell
   bin/rails server
   bundle exec sidekiq
   ```

> **WSL2 tip:** honestly, on Windows the whole native path is smoothest inside WSL2 (Ubuntu) — install Ruby via rbenv, `apt install postgresql redis-server`, then run the same `bundle`/`rails` commands there.

---

## Notes / gotchas
- **No `config/master.key`** is included (it's gitignored). You don't need it for local development — the app boots fine without it and nothing in the code reads encrypted credentials at boot.
- **Email** in development uses `letter_opener` (writes the email locally instead of sending). Emails are triggered by background jobs, so they don't block the API.
- **File storage** uses local disk in dev (no AWS keys needed). It only switches to S3 if `AWS_ACCESS_KEY_ID` is set.
- **First `docker compose up` is slow** (gem install). Later starts are fast.
