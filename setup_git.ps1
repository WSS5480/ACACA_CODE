# setup_git.ps1
# Converts THIS downloaded folder into a git working copy of the private repo,
# then puts our changes onto a branch based on the repo's real main.
#
# Safe by design: it only COMMITS the files we added or changed (additive).
#
# Requirements: Git for Windows (https://git-scm.com/download/win) and
# collaborator (write) access to the repo. The git fetch/push steps will
# prompt you to sign in to GitHub the first time.
#
# Run:  powershell -ExecutionPolicy Bypass -File setup_git.ps1

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/lagggom/acasa-api.git"
$Branch  = "feature/risk-engine-versioning-and-fixes"

Set-Location -Path $PSScriptRoot

git --version | Out-Null

if (Test-Path ".git") {
    Write-Host "This folder already has a .git - it's already a repo. Aborting so nothing gets clobbered." -ForegroundColor Yellow
    exit 1
}

Write-Host "1/7  Initializing git and adding the remote..." -ForegroundColor Cyan
git init | Out-Null
git remote add origin $RepoUrl

Write-Host "2/7  Fetching the private repo (sign in to GitHub if a window pops up)..." -ForegroundColor Cyan
git fetch origin

Write-Host "3/7  Detecting the default branch..." -ForegroundColor Cyan
git remote set-head origin -a | Out-Null
$defRef    = (git symbolic-ref --short refs/remotes/origin/HEAD)
$defBranch = $defRef -replace '^origin/',''
Write-Host "     Default branch is '$defBranch'."

Write-Host "4/7  Basing history on origin/$defBranch (working files left untouched)..." -ForegroundColor Cyan
git reset "origin/$defBranch"

Write-Host "5/7  Creating branch '$Branch'..." -ForegroundColor Cyan
git switch -c $Branch

Write-Host "6/7  Staging the files we added or changed, then committing..." -ForegroundColor Cyan
# Explicit list (both NEW and MODIFIED). We never 'git add -A' so we can't
# accidentally revert files we did not touch if this download is behind main.
$files = @(
    "docker-compose.yml",
    "Dockerfile.dev",
    "RUN_LOCALLY.md",
    "CSV_CATALOG_GUIDE.md",
    "catalog_template.csv",
    "GIT_SETUP.md",
    "CHANGES.md",
    "NOTES.md",
    "DEPLOY_VERCEL.md",
    "dev/",
    "app/controllers/api/orders_controller.rb",
    "app/sidekiq/exchange_rates/fetch_rate_job.rb",
    "config/initializers/sidekiq.rb",
    "config/initializers/rack_attack.rb",
    "config/routes.rb",
    "config/sidekiq_schedule.yml",
    "README.md",
    "app/models/concerns/credit_calculable.rb",
    "app/models/risk_engine_config.rb",
    "app/controllers/api/risk_engine_configs_controller.rb",
    "app/controllers/api/users_controller.rb",
    "app/serializers/user_serializer.rb",
    "db/migrate/",
    "public/",
    "Gemfile",
    "Gemfile.lock",
    ".rspec",
    "spec/"
)
git add -- $files
git add -f ".env.example"

Write-Host ""
Write-Host "Review the staged changes below before committing:" -ForegroundColor Yellow
git diff --cached --stat
Write-Host ""
Write-Host "If any file you did NOT intend appears above (repo moved ahead of this download)," -ForegroundColor Yellow
Write-Host "press Ctrl+C now, inspect with 'git diff --cached <file>', unstage with 'git restore --staged <file>'."
$go = Read-Host "Type 'yes' to commit and continue"
if ($go -ne 'yes') { Write-Host "Stopped before commit. Nothing pushed." -ForegroundColor DarkYellow; exit 0 }

git commit -m "Risk-engine versioning (+migrations, stamp risk_version on customers); credit/pricing fixes; automate USD-MXN rate; harden Sidekiq/rate-limit; RSpec + docs; admin pages + local dev tooling"

Write-Host ""
Write-Host "Your download may be older than the repo's current $defBranch." -ForegroundColor Yellow
Write-Host "Syncing the OTHER files to the repo version keeps your folder up to date (recommended)."
$ans = Read-Host "Type 'yes' to sync the rest of the folder to origin/$defBranch (or press Enter to skip)"
if ($ans -eq 'yes') {
    git restore --worktree .
    Write-Host "     Working tree synced to the repo." -ForegroundColor Green
} else {
    Write-Host "     Skipped. 'git status' will show the stale files as modified until you sync them." -ForegroundColor DarkYellow
}

Write-Host "7/7  Pushing branch '$Branch' to GitHub..." -ForegroundColor Cyan
git push -u origin $Branch

Write-Host ""
Write-Host "Done. GitHub printed a link above to open a pull request for '$Branch'." -ForegroundColor Green
Write-Host "From now on this folder is a normal git repo: edit, git add, git commit, git push." -ForegroundColor Green
