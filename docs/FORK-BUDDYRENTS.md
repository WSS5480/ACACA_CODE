# FORK PLAYBOOK — US rent-to-own (BuddyRents) from the ACASA codebase

Goal: stand up a second, US-domestic rent-to-own site (model: Buddy's) by FORKING this
codebase. Strategy decided 2026-08: **fork, don't multi-tenant**. Keep the ACASA repos
as a git remote and cherry-pick shared fixes across.

## Step 0 — New accounts/infrastructure (all separate from ACASA)
- 2 GitHub repos (backend fork, storefront fork — un-nest the storefront or keep the
  same layout; if nested, remember it's its own git repo).
- Render: new web service + new Postgres + the ScheduledTick cron (every 15 min:
  `bundle exec rails runner ScheduledTick.run`) + AutopayService daily cron.
- Vercel: new project → buddyrents domain.
- New Stripe account (its own STRIPE_SECRET_KEY / STRIPE_PUBLISHABLE_KEY /
  STRIPE_WEBHOOK_SECRET; point the webhook at the new backend URL).
- Messaging decision (see Step 3): new Meta WhatsApp Business number OR switch to SMS.
- Email: new sending identity (SMTP_* env vars) — do NOT reuse clientes@acasamx.com.
- Cloudflare R2 (or S3): new bucket + keys for product images and documents.
- Rainforest API key (can be shared, but budget/credits then mix — prefer separate).

Render env vars used today (set fresh values in the fork): DATABASE_URL,
DEVISE_JWT_SECRET_KEY, SECRET_KEY_BASE, STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY,
STRIPE_WEBHOOK_SECRET, SMTP_* , RAINFOREST_API_KEY (also stored in AppSetting),
R2_* , META/WHATSAPP tokens, FRONT_URL.

## Step 1 — What gets DELETED for a US-domestic model
Cross-border machinery (this is the payoff of domestic — remove, don't rebrand):
- Beneficiario ("quien recibe en México") everywhere:
  backend `app/models/beneficiary.rb`, beneficiaries_controller, kinship;
  storefront `components/Checkout/BeneficiaryForm`, `BeneficiarySelection`,
  beneficiary sections in OrderSummary, carrito, expediente views.
- FX/MXN: `app/models/exchange_rate.rb`, `app/services/fx_reprice.rb`,
  exchange_rates_controller, the hour-12 tick block, `original_price` (MXN) semantics —
  price is just USD.
- País de entrega (already Mexico-only → remove the field entirely),
  DELIVERY_COUNTRY_OPTIONS in utils/prequalificationOptions.js.
- MX references requirement (2 MX + 2 US referrals) → decide the US rule (e.g. 4 US).
- Mexican legal template: `db/templates/` contract text, privacy policy in AppSetting
  (LFPDPPP is Mexican law) → replace with US rent-to-own agreement + state disclosures.
  ⚠ US rent-to-own is state-regulated (RTO disclosure laws, price caps in some states)
  — get the contract and fee disclosures from a lawyer, don't port the Mexican one.
- IVA → US sales tax semantics (Product.tax_rate exists; rename labels, receipts say
  "Tax" not "IVA"; nexus/rates per state is a business decision).

## Step 2 — What gets TRANSLATED/REBRANDED (inventory, 2026-08 scan)
Language: the whole storefront + admin + WhatsApp/mail templates are Spanish → English.
Highest-density brand/domain references (grep `acasa|acasamx|wa.me|8118247975`):
- Storefront: pages/perfil.js (11), contratos/[id]/pagar.js (10), contratos/[id]/index.js
  (8), index.js (7), pago-inicial.js (7), carrito.js (7), como-funciona.js, soporte.js,
  wa.js, privacidad.js, firmar.js, datos.js, pagos.js, AdminSidebar, axiosFunctions
  (API base URL), next.config.js (admin redirect → onrender host).
- Backend: all mailers (application_mailer from-address, user_mailer, accounting_mailer,
  logo_attachable → `public/acasa_logo_mail.png`), whatsapp_* services, wa_alert,
  reference_survey, rainforest_import_service, `public/admin.html` (title, logo, texts),
  receipts in admin.html + contratos/[id]/index.js (logo, WhatsApp number, emails).
- Brand assets: public/acasa-icon.svg, acasa_logo_mail.png, www-acasa-main/public/
  acasa-icon.svg, /landing/hero-*.jpg (shoot/compose new photos — the neon arrow is
  baked into the images), promo-pattern.png.
- Colors: storefront constants in pages/index.js (NAVY/ORANGE/AMBER/…), tailwind.config
  (bg-nav-blue, text-orange…), src/styles.css (banner, V2 classes), admin.html CSS vars.
- Banner phrases (Navbar marquee) + /como-funciona pitch — rewrite for US audience
  ("no credit needed", "weekly payments", "own it or return it anytime" model).

## Step 3 — Product decisions before coding
1. Messaging channel: WhatsApp penetration is lower for a general US audience — likely
   SMS (Twilio) for verification + reminders. The WhatsApp gate
   (TokenAuthenticatable wa_unverified) becomes an SMS OTP gate; whatsapp_* services
   get a Twilio sibling. This is the biggest engineering delta of the fork.
2. Rent-to-own mechanics: ACASA's engine already IS lease-to-own (weekly/biweekly/
   monthly, finance_factor 1.25, early-payoff "saldo" mode that rebates the factor —
   that's effectively an Early Purchase Option). Missing for Buddy's parity: EPO as a
   named customer-facing option (payments.kind 'epo' is already reserved in the ledger),
   same-as-cash window, return/charge-off flow is present (returned/charged_off).
3. Delivery: local delivery/pickup instead of cross-border freight — the order pipeline
   step "Entrega 🚚" stays, logistics behind it changes.
4. Catalog: Amazon-sourced via Rainforest works as-is (US market native — simpler).

## Step 4 — Suggested order of work (Claude Code, locally)
1. Fork repos; global rename + English pass (mechanical, big diff).
2. Delete cross-border modules (Step 1 list); run the test flows end-to-end.
3. SMS verification swap.
4. New brand assets + colors + copy; legal contract template.
5. New infra env vars; deploy; run migrations; seed catalog via the scraper.
Keep `utils/uiV2.js` pattern: new risky UI goes behind flags with a revert switch.

## Shared-fix discipline
`git remote add acasa <acasa-repo-url>` in the fork. When a bug is fixed in either
codebase, cherry-pick to the other the same week. The accounting engine, credit engine,
scraper and admin are 90% shared — treat them as a de-facto common core.
