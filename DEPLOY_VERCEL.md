# Deploy the customer demo to Vercel (public link for partners)

The storefront (`public/index.html`, `shop.html`, hero images) is static and pulls the
live catalog from `api.acasa.mx`. Your API's CORS allows **any `*.vercel.app`** origin, so
any Vercel deployment will show real products. No backend needed for the demo.

## Prerequisite
Node.js installed. Check by opening PowerShell and typing `node -v`. If it prints a version,
you're set. If not, install the LTS from https://nodejs.org and reopen PowerShell.

## Deploy (one time)

1. Open the **public** folder in File Explorer:
   `C:\Users\steve\OneDrive\Desktop\acasa-api-main\public`
2. Click the address bar, type `powershell`, press Enter.
3. Log in to Vercel (opens your browser to authenticate):
   ```
   npx vercel login
   ```
4. Deploy to production:
   ```
   npx vercel --prod
   ```
   Answer the prompts:
   - Set up and deploy? **Y**
   - Which scope? **(your account)**
   - Link to existing project? **N**
   - Project name? **acasa-demo** (or anything — the URL will end in `.vercel.app`)
   - In which directory is your code located? **./** (just press Enter)
5. When it finishes it prints a **Production URL** like `https://acasa-demo.vercel.app`.
   That's the link to share with partners.

## Redeploy after changes
Any time you change the files, run `npx vercel --prod` again in the same folder.

## Notes
- The demo browses your **real live catalog and photos** and calculates real payment plans.
- "Solicitar" (apply) shows a demo confirmation — it does not create real accounts on the demo.
- The "Admin" link is a local tool and won't work on the public demo; that's expected.
