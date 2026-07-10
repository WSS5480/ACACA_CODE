# Changes in this branch

Improvements made with Claude, plus local dev tooling. Everything is additive or a
targeted edit — no existing feature was removed.

## 1. Bug / logic fixes
- **Float-safe money checks** (`app/controllers/api/orders_controller.rb`): the order-create
  and `simulate_payment_plans` validations compared prices with exact `==` on floats, which
  can reject legitimate requests (e.g. 299.999 vs 300.00). Now compared to the cent via a
  `money_equal?` helper.
- **Real dashboard `credits_count`**: was hardcoded to `0`. Now counts clients with store
  credit > 0, honoring the same date filter as the other metrics.

## 2. Automation
- **Daily USD→MXN exchange rate** (`app/sidekiq/exchange_rates/fetch_rate_job.rb`): fetches the
  rate from a no-key API and stores a new `ExchangeRate` only when it changes. Wired into
  sidekiq-scheduler (`config/sidekiq_schedule.yml`, enabled in `config/initializers/sidekiq.rb`).
  Runs daily at 12:00. Source URL overridable with `EXCHANGE_RATE_API_URL`.

## 3. Security hardening
- **Sidekiq UI** (`config/routes.rb`): no longer ships a default `admin`/`password` login. In
  production it requires `SIDEKIQ_USERNAME` and `SIDEKIQ_PASSWORD`; if they're unset, the
  `/sidekiq` panel is simply not mounted. Dev keeps the convenient default.
- **Rate limiting** (`config/initializers/rack_attack.rb`): replaced dead throttles (for a
  `/events/.../checkin` route that doesn't exist here) with real per-IP throttles on
  `/api/login`, `/api/signup`, and `/api/password`.

## 4. Tests + docs
- **RSpec** added (`Gemfile`, `.rspec`, `spec/`): specs for the pricing engine, the simulator
  endpoint, `ExchangeRate`, and the exchange-rate job (HTTP stubbed with WebMock).
- **Real README** replacing the Rails boilerplate.

## ⚠️ Needs a business decision (not changed)
The pricing formula in `Product#calculate_weekly_payment` has a quirk: because
`downpayment + used_credit` is forced to equal the price, the financed amount works out to
`price × turns − 2 × downpayment`, so **applying store credit (which lowers the downpayment)
raises the weekly payment**. A spec documents the current behavior (`spec/models/product_spec.rb`)
but I did not change the math — changing a lending formula needs Acasa's sign-off. Tell me the
intended behavior and I'll adjust it with a test.

---

## Do this BEFORE deploying (important)

We added gems (`rspec-rails`, `factory_bot_rails`, `webmock`), so `Gemfile.lock` must be
regenerated or Hatchbox's `bundle install` will fail.

**Recommended order:**
1. Run it locally first — this also updates `Gemfile.lock`:
   ```
   docker compose up --build
   ```
2. Run the tests:
   ```
   docker compose exec web bundle exec rspec
   ```
3. Then commit/push with `setup_git.ps1` (it stages the updated `Gemfile.lock`).

If you commit before step 1, the lock won't include the new gems and the deploy will fail.

## Production env vars to set in Hatchbox
- `SIDEKIQ_USERNAME`, `SIDEKIQ_PASSWORD` — required to keep the `/sidekiq` dashboard available.
- `EXCHANGE_RATE_API_URL` — optional; a sensible default is built in.

## Deploy
Merge the branch and Hatchbox redeploys (see `DEPLOYMENT.md`). The exchange-rate cron needs a
running Sidekiq process (already part of your setup).
