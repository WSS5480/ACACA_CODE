# Connecting this folder to the GitHub repo

This folder is currently a plain unzipped download — no git history, not linked to
`https://github.com/lagggom/acasa-api.git` (which is **private**). These steps turn it
into a real git working copy so you can commit and push changes.

## Before you start
- **Git for Windows** installed: https://git-scm.com/download/win (includes the sign-in helper).
- **Write access** to the repo (you're a collaborator on the `lagggom` org). If you only
  have read access, `git push` will be rejected and you'd need to fork instead.
- You do **not** need to hand me any credentials — GitHub asks *you* to sign in (a browser
  window) the first time git talks to the private repo.

## The easy way (script)

From this folder, run:

```powershell
powershell -ExecutionPolicy Bypass -File setup_git.ps1
```

It initializes git, fetches the real repo, creates a branch called
`chore/local-dev-tooling`, commits **only the files we added**, optionally brings the rest
of the folder up to date with the repo, and pushes the branch. At the end GitHub prints a
link to open a pull request.

## The manual way (same thing, step by step)

```powershell
cd "$env:USERPROFILE\OneDrive\Desktop\acasa-api-main"

git init
git remote add origin https://github.com/lagggom/acasa-api.git

git fetch origin                       # sign in to GitHub if prompted

# base our history on the repo's default branch (main) without touching your files:
git reset origin/main                  # if the default branch is 'master', use that instead

git switch -c chore/local-dev-tooling

# stage only the files we added (additive — nothing existing is changed):
git add docker-compose.yml Dockerfile.dev RUN_LOCALLY.md CSV_CATALOG_GUIDE.md catalog_template.csv dev/
git add -f .env.example                # it's covered by .gitignore, so force-add the example
git commit -m "Add local dev tooling: Docker dev stack, run guide, CSV catalog guide, scraper demo"

# (optional but recommended) sync the OTHER files to the repo's current main,
# discarding the older downloaded copies. Our new files stay committed:
git restore --worktree .

git push -u origin chore/local-dev-tooling
```

Then open the pull-request link GitHub prints.

## Why a branch + pull request (not a push straight to main)?
It lets a teammate review the change, keeps `main` stable, and is easy to undo. If your
team just pushes to `main` directly, you can instead do `git switch main` before committing
and `git push origin main` — but a branch is the safer default.

## What actually gets committed
Only the files we created in this session — all additive, zero edits to existing code:

- `docker-compose.yml`, `Dockerfile.dev`, `.env.example` — one-command local dev stack
- `RUN_LOCALLY.md` — Windows run guide
- `CSV_CATALOG_GUIDE.md`, `catalog_template.csv` — CSV catalog workflow
- `dev/` — sample scraper payload + catalog-generation scripts

## After setup
This becomes a normal repo. Day-to-day:

```powershell
git pull                 # get teammates' changes
# ...make edits (here with me, or in VS Code)...
git add -A
git commit -m "describe your change"
git push
```

> **OneDrive note:** git works inside a OneDrive folder, but the `.git` folder syncing can
> occasionally be slow. If you hit odd git errors, pausing OneDrive sync while you work, or
> moving the repo outside OneDrive (e.g. `C:\dev\acasa-api`), avoids it.
