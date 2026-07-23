# Ácasa — findings & notes

Working notes from the local setup + investigation session. Keep for reference / to share with Lagom.

## Where things are hosted

**Production API — `api.acasa.mx`** (this is the REAL one the live site uses)
- Provider: **DigitalOcean** (ASN 14061), IP `192.241.162.211`
- Region: DigitalOcean **NYC** datacenter — physically Secaucus, New Jersey, USA
- Stack: **Ubuntu + nginx**, Rails app served directly (no Cloudflare in front)
- Deployed via **Hatchbox** (per DEPLOYMENT.md); by Hatchbox default the **PostgreSQL DB runs on the same droplet**
- Managed by **Lagom** (the dev studio, lagggom.com)

**Old API — `acasa-api.lagggom.com`** (DEAD / legacy)
- Returns **Cloudflare error 525 (SSL handshake failed)** — origin unreachable
- Sits behind Cloudflare (different setup than the real API)
- The **codebase still defaults to this URL** (e.g. `API_HOST` in config) — should be removed/repointed to `api.acasa.mx`

**Local dev**
- PostgreSQL 16 in Docker on this laptop (`db` service, DB `acasa_api_development`)
- Test signups from the local storefront land here, not production

## Where customer records live
- Real customers: `users` table (+ `credits`, `orders`, `buyers`, `guarantors`, `referrals`, `beneficiaries`) in the **production Postgres on the DigitalOcean droplet (New Jersey)**
- Passwords stored encrypted (bcrypt / Devise), not plaintext

## Questions / risks to raise with Lagom
1. **Backups** — is the production database backed up automatically, and stored **off the droplet** (e.g. DO Spaces/S3)? App + DB on one VPS = single point of failure.
2. **The dead `acasa-api.lagggom.com`** — confirm it can be retired and purge it from the codebase/DNS so nothing points at it.
3. **Data residency** — MX/US customer PII + financial data is stored in the US (New Jersey). Note for any compliance question.
4. **Canonical API URL** — standardize on `api.acasa.mx` across code and config.

## Improvements built this session (on a branch, not yet deployed)
See `CHANGES.md` for detail. Summary:
- Bug fixes: float-safe price checks; real dashboard `credits_count` (was hardcoded 0)
- Automation: daily USD→MXN exchange-rate job (sidekiq-scheduler)
- Security: Sidekiq UI no longer ships default admin/password in production; rate limiting on login/signup/password
- Tests: RSpec suite (pricing engine, simulator, exchange rate, fetch job) + real README
- Flagged (needs business decision): pricing formula where applying store credit *raises* the weekly payment

## Local tooling built
- `docker-compose.yml` + `Dockerfile.dev` — one-command local stack (`docker compose up --build`)
- `public/playground.html` — API playground (localhost:3000/playground.html)
- `public/shop.html` — customer storefront; now reads the **live `api.acasa.mx` catalog** (real products + photos), payment simulator uses the live pricing engine; signups write to the local test DB only
- `RUN_LOCALLY.md`, `CSV_CATALOG_GUIDE.md`, `dev/` (scraper demo), `GIT_SETUP.md`, `setup_git.ps1`

## Handy references
- Live catalog API: `https://api.acasa.mx/api/products?status=active&per_page=200`
- Local app: `http://localhost:3000` · storefront `/shop.html` · playground `/playground.html` · Sidekiq `/sidekiq` (admin/password)
- Local test logins: client `cliente@test.com` / `password123` (num 123456) · admin `admin@test.com` / `admin123`
