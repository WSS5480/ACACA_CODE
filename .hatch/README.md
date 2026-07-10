# Hatchbox Deployment Configuration

## Bundler 4.0+ Compatibility

This directory contains scripts to handle Bundler 4.0+ compatibility during deployment.

### Problem

Hatchbox's deploy script executes `bundle install --deployment`, but Bundler 4.0+ removed the `--deployment` flag. Instead, you need to use `bundle config set deployment true`.

### Solution

You need to configure Hatchbox to run the configuration script before installing gems, or modify the deploy command in Hatchbox settings.

### Option 1: Update Hatchbox Deploy Command

In your Hatchbox project settings, update the deploy command to:

```bash
.hatch/configure_bundler.sh && bundle install
```

### Option 2: Manual Configuration

SSH into your server and run:

```bash
cd /home/deploy/acasa-api
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'
```

### Files

- `configure_bundler.sh` - Script to configure Bundler before install
- `deploy.sh` - Custom deploy script (if Hatchbox supports it)
- `pre_deploy.sh` - Pre-deploy hook (if Hatchbox supports it)
