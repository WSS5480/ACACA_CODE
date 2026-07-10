# Deployment Notes

## Bundler 4.0+ Compatibility

This project uses Bundler 4.0+, which removed the `--deployment` flag. 

### Configuration

The project includes a `.bundle/config` file that configures deployment mode automatically. This file should be committed to the repository.

### Hatchbox Deployment Fix

**IMPORTANT**: Hatchbox's deploy script executes `bundle install --deployment`, which fails with Bundler 4.0+.

#### Solution: Update Hatchbox Deploy Command

In your Hatchbox project settings, you need to modify the deploy command to configure bundle before installing:

1. Go to your Hatchbox project settings
2. Find the "Deploy Command" or "Build Command" section
3. Replace the default command with:
   ```bash
   bundle config set --local deployment true && bundle config set --local path vendor/bundle && bundle config set --local without 'development test' && bundle install
   ```

   Or use the provided script:
   ```bash
   .hatch/configure_bundler.sh && bundle install
   ```

#### Alternative: Manual Server Configuration

If you can't modify the Hatchbox deploy command, SSH into your server and run:

```bash
cd /home/deploy/acasa-api
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle config set --local without 'development test'
```

This will persist the configuration for future deployments.

### Files Included

- `.bundle/config` - Bundler configuration file (committed to repo)
- `.hatch/configure_bundler.sh` - Script to configure bundle before install
- `.hatch/deploy.sh` - Custom deploy script (if Hatchbox supports it)
- `bin/deploy` - Deployment script that configures bundle correctly
- `bin/bundle` - Bundle wrapper that removes deprecated flags

### Important Notes

- The `--deployment` flag is **deprecated** and will cause deployment to fail
- Bundle will automatically read `.bundle/config` if present
- The deployment configuration is set via `bundle config set deployment true` instead
- **You must update your Hatchbox deploy command** to avoid the `--deployment` flag
