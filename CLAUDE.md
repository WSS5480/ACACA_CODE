# CLAUDE.md — ACASA backend (Rails API + admin)

ACASA (acasamx.com) is a cross-border BNPL / rent-to-own platform: customers in the USA
buy on credit, goods are delivered to their family in Mexico. This repo is the Rails 7.1
API + the staff admin panel. The Next.js storefront lives in `www-acasa-main/` (its own
git repo nested inside this one — commit and push it separately).

## Deployments
- Backend: Render web service **ACASA-WEB** (srv-d98jk65aeets7383jt8g), Postgres
  dpg-d98jjt5aeets7383jikg-a. Push to `main` on GitHub → auto-deploy.
- Storefront: Vercel project **acasa-frontend** → www.acasamx.com. Push `www-acasa-main`
  `main` → auto-deploy.
- Admin: `public/admin.html`, served by Rails at acasa-web.onrender.com/admin.html
  (`/admin` on the storefront redirects there — see next.config.js).
- **Migrations are run MANUALLY**: deploy first, then open a fresh Render Shell and run
  `bin/rails db:migrate`, then redeploy/restart so all processes pick up new columns.
  Because code can deploy before its migration runs, serializers/models must be
  DEFENSIVE about new columns (`respond_to?`, `column_names.include?`, `try`).

## Money model (the heart — do not guess, read this)
- Product: `price` (USD, derived), `original_price` (MXN), `price_with_discount`,
  `turns`, `decimal_factor`. Cash price ("contado") = cost × turns × decimal_factor
  (fallback 0.75); `total_price` when present is authoritative.
- Contract: `total_amount` (contado), `downpayment`, `financed_amount` =
  (contado − enganche) × **finance_factor (1.25)**. The CREDIT LINE covers the FULL
  financed amount; any excess over available credit goes to the down payment
  (creditFloor = ceil((total − credit/1.25)×100)/100 in carrito.js).
- Payments: `payments.amount` is the BASE applied to amortization. Accounting columns:
  `kind` (enganche|renta|contado|liquidacion|epo), `iva_amount`, `extra_amount`
  (exención de responsabilidad = waiver), `total_charged`, `stripe_fee`, `fx_rate`.
  Kind is auto-classified in `Payment#set_accounting_fields`.
- Ledger: `ledger_entries` is APPEND-ONLY (survives contract deletion). Corrections are
  counter-entries (see AccountingController#void_payment / #modify_payment), never edits.
  Daily/monthly closes (`accounting_closes`) run from ScheduledTick just after midnight
  Monterrey; closed periods are immutable.
- FX: ExchangeRate.current_rate; FxReprice.run! reprices the whole MXN catalog + unpaid
  contracts daily (tick hour 12 Monterrey) and on manual refresh.
- Waiver ("Exención de responsabilidad", NEVER "seguro"): % on each order; charged on
  single payments, autopay, combined payments (stripe_controller) — all three paths.

## Key flows
- Signup = prequalification (pages/signup.js) → risk engine assigns credit → WhatsApp
  verification HARD GATE (TokenAuthenticatable returns 403 `wa_unverified` for
  unconfirmed clientes; staff can override via users#confirm_account) → auto-login →
  cart. Contracts are created at checkout as unpaid orders (reserve credit) and become
  real after `initial_paid?`.
- Order pipeline (ProcessRibbon, 6 steps): Precalifica → Pago inicial → Completa tu
  orden (datos + 4 referencias) → Verificamos tu información → Aprobación final +
  firma → Entrega.
- Amazon import (Rainforest): flags stamped ON the product AT DOWNLOAD (sold_by_amazon,
  delivered_by_amazon, main_photo_ok), main photo downloaded first, 1 credit per item.
  NO automatic paid ticks — weekly price refresh is a MANUAL admin button.
  Amazon blocks free page checks from Render IPs (CatalogPatrol exists but is disabled).
- ScheduledTick runs every 15 min via Render cron: commitment reminders (hour 9),
  FX fetch+reprice (hour 12), accounting closes (hour 0). Keep new jobs idempotent.

## Gotchas that have bitten us (respect these)
- `public/admin.html` is CRLF. Convert to LF to edit, back to CRLF to deliver. It's one
  giant file with one <script>; validate by extracting the script and `node --check`.
- Storefront global CSS is **src/styles.css** (imported by pages/_app.js).
  `styles/globals.css` is DEAD — never edit it.
- Navbar renders through createPortal AFTER mount — effects that need its DOM must not
  assume first-render availability. The scrolling banner uses rAF + scrollLeft in whole
  pixels (CSS transform animation blurs text on Windows ClearType).
- Never compute `new Date()` in render paths of SSR pages — the countdown on
  pages/index.js caused intermittent full-page hydration rebuilds on mobile.
- Hero collage photos must keep their intrinsic aspect-ratio boxes (994/761, 1245/855);
  minHeight distorts the geometry (the neon arrow is baked INTO the photos).
- JSX: no `//` comments inside single-line style objects.
- Admin JWT expires; the panel now drops to the login screen on 401 token errors.

## Brand rules (Steve's standing rules)
- Brand is written **acasa** — NEVER "ácasa" with an accent. Official logo:
  `public/acasa_logo_mail.png` (same as email header) — use the image, not styled text.
- wa.me links: do NOT prepend "1" to US numbers (WhatsApp adds it).
- Nothing is destroyed: archive/move, don't delete ("keep archived"). Testing-phase
  delete tools are marked "QUITAR ANTES DEL GO-LIVE" (search that string).
- No fabricated content on the live site: stats counters (V2_STATS) and testimonials
  (V2_TESTIMONIOS) stay OFF until real figures/quotes exist.
- Every delivery ends with the exact terminal push commands.

## Storefront V2 redesign switch
`www-acasa-main/utils/uiV2.js` — `UI_V2=false` reverts the whole 2026-08 redesign
(cards v2, hero mesh, animations, skeletons, sticky CTA). Git tag `pre-v2` = fa323b9.

## Go-live checklist (pending)
- Remove PURGE-CLIENTE block and the accounting real-delete (🗑) tool.
- Set STRIPE_PUBLISHABLE_KEY (Render) and NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY (Vercel).
- Rotate any credentials that ever passed through chat (list with Steve).
- /terminos page is a dead link on signup; footer Términos points to /productos.
