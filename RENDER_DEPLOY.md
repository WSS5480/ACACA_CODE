# Deploy the full app to Render

This runs the WHOLE app off your machine - Rails API + PostgreSQL + Redis + Sidekiq -
so every page works, including the admin tools. The `render.yaml` blueprint wires all
four pieces together.

## Steps

1. Commit the blueprint to your repo (from the project root):
   ```
   git add -A
   git commit -m "Add Render blueprint for full-stack deploy"
   git push
   ```

2. Create a Render account: https://dashboard.render.com/register (sign in with GitHub).

3. In Render: click **New +** -> **Blueprint** -> connect and pick the
   **WSS5480/ACACA_CODE** repo -> **Apply**.
   Render reads `render.yaml`, provisions the database + Redis, builds from your
   Dockerfile, and deploys the web + worker services.

4. First build takes ~5-10 minutes. When it's done, open the **acasa-web** service -
   its URL (like `https://acasa-web-xxxx.onrender.com`) is your live app.
   Everything works there: storefront, admin, credit + risk pages, the API, and the DB.

## Notes

- **Cost:** everything starts on **free** plans ($0). Free services *sleep when idle*, so
  the first request after a pause is slow. For always-on, bump the `plan:` lines in
  `render.yaml` (web/worker -> `starter`, db -> `basic-256mb`, redis -> `starter`), roughly
  $20-30/mo total.
- **Migrations run automatically** on first boot (the Dockerfile runs `db:prepare`), which
  also seeds the risk-engine versions (v1 + v2).
- **Optional env vars** you can add later in the Render dashboard if you need those features:
  - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` / `AWS_S3_BUCKET` - product image uploads (S3)
  - `SMTP2GO_USERNAME` / `SMTP2GO_PASSWORD` - outgoing email (welcome, password reset)
  - `ALLOWED_ORIGINS` - restrict CORS to your frontends
- First production deploys sometimes need a small tweak (health check, an env var). If a
  service shows an error in its **Logs**, paste it and we'll fix it.
