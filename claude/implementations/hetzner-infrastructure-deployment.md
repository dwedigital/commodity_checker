# Hetzner Infrastructure Deployment Guide

**Date:** 2026-01-20
**Feature:** Migration from Render to Hetzner VPS + Managed PostgreSQL
**Status:** ✅ Production and Staging LIVE

## Current Status

| Environment | URL | Status | Server IP | Database |
|-------------|-----|--------|-----------|----------|
| Production | https://tariffik.com | ⏳ DNS pending | 116.203.77.140 | DigitalOcean Managed PostgreSQL |
| Staging | https://staging.tariffik.com | ✅ Live | 91.99.171.192 | DigitalOcean Managed PostgreSQL |

**Deployment Date:** 2026-01-20
**Monthly Savings:** ~$55/month (from ~$70 → ~$15.50)

---

## ⚠️ CRITICAL: Lessons Learned from Staging Deployment

These issues were discovered during staging deployment and MUST be addressed before production deployment.

### 1. Database Connection Pool Exhaustion

**Problem:** PostgreSQL ran out of connections with error:
```
FATAL: remaining connection slots are reserved for roles with the SUPERUSER attribute
```

**Root Cause:** Default Rails configuration opens too many connections:
- Each Puma worker opens connections for: primary, queue, cache, cable databases
- Default `WEB_CONCURRENCY` can spawn multiple workers
- DigitalOcean managed PostgreSQL has limited connection slots (~25 for basic tier)

**Solution:** Configure connection limits explicitly in deployment config:

**config/deploy.staging.yml** (and deploy.yml for production):
```yaml
env:
  clear:
    WEB_CONCURRENCY: 0          # Single-mode Puma (no forking)
    RAILS_MAX_THREADS: 5        # Threads per worker
```

**config/database.yml:**
```yaml
production:
  primary: &production_primary
    <<: *default
    adapter: postgresql
    encoding: unicode
    url: <%= ENV["DATABASE_URL"] %>
    idle_timeout: 300        # Close connections idle for 5 minutes
    reaping_frequency: 30    # Check for stale connections every 30 seconds
  queue:
    <<: *production_primary
    pool: 5                  # Solid Queue needs 5 threads - DO NOT REDUCE
    migrations_paths: db/queue_migrate
  cache:
    <<: *production_primary
    pool: 2                  # Cache uses minimal connections
    migrations_paths: db/cache_migrate
  cable:
    <<: *production_primary
    pool: 2                  # Cable rarely used heavily
    migrations_paths: db/cable_migrate
```

**Key Points:**
- `WEB_CONCURRENCY=0` means single-mode Puma (no worker processes, just threads)
- `WEB_CONCURRENCY=1` causes warnings: "Puma is running in single mode with 1 worker"
- **Solid Queue REQUIRES pool: 5** - setting it lower crashes the app with:
  ```
  Solid Queue is configured to use 5 threads but the database connection pool is 3
  ```

**Connection Math:**
- Single-mode Puma with 5 threads = up to 5 connections per database
- 4 databases (primary, queue, cache, cable) × 5 connections = 20 connections max
- Plus: `idle_timeout` and `reaping_frequency` ensure connections are released

**Emergency Recovery:** If connections are exhausted, terminate them via psql:
```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'your_database'
AND pid <> pg_backend_pid();
```

---

### 2. Image Processing: MiniMagick vs Vips

**Problem:** Image variants returned broken links with error:
```
MiniMagick::Error - executable not found: "convert"
```

**Root Cause:** The Dockerfile installs `libvips` but Rails was configured to use `mini_magick` (ImageMagick).

**Solution:** In `config/application.rb`:
```ruby
# Use vips for image processing (libvips is installed in Docker image)
config.active_storage.variant_processor = :vips
```

**Verification:** Ensure Dockerfile has `libvips` in runtime dependencies:
```dockerfile
RUN apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 libpq5
```

**Note:** If you switch to `:vips`, you cannot use MiniMagick-specific transformations. The vips API is slightly different but covers most use cases.

---

### 3. Kamal Builds from Committed Code Only

**Problem:** Changes weren't deploying even after running `kamal deploy`.

**Root Cause:** Kamal clones the git repository and builds from committed code. Uncommitted changes are ignored with warning:
```
Building from a local git clone, so ignoring these uncommitted changes:
 M config/application.rb
 ?? new_file.rb
```

**Solution:** Always commit changes before deploying:
```bash
git add -A && git commit -m "Description" && kamal deploy -d staging
```

**Tip:** Create a deployment alias:
```bash
alias deploy-staging="git add -A && git commit -m 'Deploy staging' && kamal deploy -d staging"
```

---

### 4. Environment-Specific Webhook Secrets

**Problem:** Staging inbound emails weren't being verified correctly.

**Root Cause:** Both environments were using the same Resend webhook secret, but staging needs its own webhook endpoint with its own secret.

**Solution:**
1. Create separate Resend webhook for staging pointing to:
   `https://staging.tariffik.com/rails/action_mailbox/resend/inbound_emails`
2. Store staging-specific secret in `.kamal/secrets.staging`:
   ```bash
   RESEND_WEBHOOK_SECRET=whsec_staging_specific_secret_here
   ```
3. Production uses its own secret in `.kamal/secrets`:
   ```bash
   RESEND_WEBHOOK_SECRET=whsec_production_secret_here
   ```

**Important:** Each Resend webhook endpoint generates its own signing secret. Don't reuse secrets across environments.

---

### 5. Deploy Lock Recovery

**Problem:** Deploy failed mid-way and subsequent deploys fail with lock error:
```
Deploy lock already acquired
```

**Solution:**
```bash
kamal lock release -d staging    # For staging
kamal lock release -d production # For production
```

---

### 6. Storage Configuration (Hetzner Object Storage)

**Problem:** Images uploaded but not accessible.

**Current Setup:** Using Hetzner Object Storage (S3-compatible) in Nuremberg (nbg1).

**config/storage.yml:**
```yaml
hetzner:
  service: S3
  access_key_id: <%= ENV["HETZNER_STORAGE_ACCESS_KEY_ID"] %>
  secret_access_key: <%= ENV["HETZNER_STORAGE_SECRET_ACCESS_KEY"] %>
  region: <%= ENV.fetch("HETZNER_STORAGE_REGION", "fsn1") %>
  bucket: <%= ENV["HETZNER_STORAGE_BUCKET"] %>
  endpoint: <%= ENV["HETZNER_STORAGE_ENDPOINT"] %>
  force_path_style: true
```

**Deployment config:**
```yaml
env:
  secret:
    - HETZNER_STORAGE_ACCESS_KEY_ID
    - HETZNER_STORAGE_SECRET_ACCESS_KEY
  clear:
    HETZNER_STORAGE_BUCKET: tariffik
    HETZNER_STORAGE_REGION: nbg1
    HETZNER_STORAGE_ENDPOINT: https://nbg1.your-objectstorage.com
```

**Note:** `force_path_style: true` is required for Hetzner Object Storage.

---

## Pre-Production Deployment Checklist

Before deploying to production, verify ALL of these:

### Configuration Files
- [ ] `config/application.rb` has `variant_processor = :vips`
- [ ] `config/database.yml` has correct pool sizes (queue: 5, cache: 2, cable: 2)
- [ ] `config/database.yml` has `idle_timeout: 300` and `reaping_frequency: 30`
- [ ] `config/deploy.yml` has `WEB_CONCURRENCY: 0` and `RAILS_MAX_THREADS: 5`
- [ ] `config/storage.yml` has `force_path_style: true` for Hetzner

### Secrets Files
- [ ] `.kamal/secrets` has production `DATABASE_URL`
- [ ] `.kamal/secrets` has production `RESEND_WEBHOOK_SECRET`
- [ ] `.kamal/secrets` has `HETZNER_STORAGE_ACCESS_KEY_ID` and `SECRET_ACCESS_KEY`
- [ ] All API keys are production keys (not staging/test)

### Pre-Deploy
- [ ] All code changes are committed (`git status` shows clean)
- [ ] Staging has been tested with same configuration
- [ ] Database migrations are backwards-compatible (see CLAUDE.md)

### Post-Deploy Verification
- [ ] Site loads with valid SSL
- [ ] User login works
- [ ] Image upload and variant generation works
- [ ] Inbound email processing works
- [ ] Background jobs are processing (check logs)
- [ ] No database connection errors in logs

---

## Post-Deploy Console Verification

After deploying, open the Rails console to verify the system is healthy:

```bash
kamal console -d production   # or -d staging
```

### 1. Database Connection
```ruby
ActiveRecord::Base.connection.execute("SELECT 1").first
# Should return {"?column?"=>1} or similar
```

### 2. Connection Pool Status
```ruby
ActiveRecord::Base.connection_pool.stat
# Should show {size: 5, connections: X, busy: X, dead: 0, idle: X, waiting: 0}
# Connections should be low, dead should be 0
```

### 3. All Databases Connect
```ruby
[:primary, :queue, :cache, :cable].each do |db|
  result = ActiveRecord::Base.connected_to(database: db) { ActiveRecord::Base.connection.active? }
  puts "#{db}: #{result}"
end
# All should return true
```

### 4. Solid Queue Running
```ruby
SolidQueue::Process.count
# Should be > 0 if queue is running in Puma
```

### 5. Data Integrity Check
```ruby
User.count
Order.count
# Should match expected counts from old server
```

### 6. Recent Activity
```ruby
Order.order(created_at: :desc).limit(3).pluck(:id, :created_at)
# Verify recent orders are present
```

### 7. Image Processing (vips)
```ruby
Rails.application.config.active_storage.variant_processor
# Should return :vips

# Verify libvips library is installed
`dpkg -l | grep vips`.strip
# Should show libvips package

# If you have blobs, test one
blob = ActiveStorage::Blob.last
blob.present? && blob.variable?
# Should return true for image blobs
```

### 8. Storage Connection (Hetzner)
```ruby
ActiveStorage::Blob.service.class.name
# Should return "ActiveStorage::Service::S3Service"

ActiveStorage::Blob.count
# Should match expected count
```

### 9. API Keys Configured
```ruby
ENV['ANTHROPIC_API_KEY'].present?
ENV['RESEND_API_KEY'].present?
ENV['HETZNER_STORAGE_ACCESS_KEY_ID'].present?
# All should return true
```

---

## Architecture

```
                    +----------------------------------------+
                    |    DigitalOcean Managed PostgreSQL     |
                    |    (Frankfurt - fra1)                  |
                    +----------------------------------------+
                    |  tariffik_production (production DB)   |
                    |  tariffik_staging (staging DB)         |
                    +-----------------+----------------------+
                                      |
                    +-----------------+----------------------+
                    |                                        |
                    v                                        v
+-------------------------------+          +-------------------------------+
|     Production Server         |          |      Staging Server           |
|     Hetzner CPX32 (Helsinki)  |          |      Hetzner CPX22 (Helsinki) |
|     4 vCPU, 8GB RAM, x86/AMD  |          |      2 vCPU, 4GB RAM, x86/AMD |
+-------------------------------+          +-------------------------------+
|  kamal-proxy (TLS termination)|          |  kamal-proxy (TLS termination)|
|  +---------------------------+|          |  +---------------------------+|
|  |  Tariffik App Container   ||          |  |  Tariffik App Container   ||
|  |  - Rails 8 + Puma         ||          |  |  - Rails 8 + Puma         ||
|  |  - Solid Queue in Puma    ||          |  |  - Solid Queue in Puma    ||
|  |  - Single-mode (no fork)  ||          |  |  - Single-mode (no fork)  ||
|  +---------------------------+|          |  +---------------------------+|
|                               |          |                               |
|  tariffik.com                 |          |  staging.tariffik.com         |
|  Let's Encrypt SSL            |          |  Let's Encrypt SSL            |
+-------------------------------+          +-------------------------------+

                    +----------------------------------------+
                    |      Hetzner Object Storage            |
                    |      (Nuremberg - nbg1)                |
                    |      Bucket: tariffik                  |
                    +----------------------------------------+
```

---

## Configuration Summary

| Setting | Production | Staging |
|---------|------------|---------|
| Domain | tariffik.com | staging.tariffik.com |
| Server IP | 116.203.77.140 | 91.99.171.192 |
| Server Type | CPX32 (4 vCPU, 8GB) | CPX22 (2 vCPU, 4GB) |
| Database | tariffik_production | tariffik_staging |
| WEB_CONCURRENCY | 0 | 0 |
| RAILS_MAX_THREADS | 5 | 5 |
| Object Storage | Hetzner nbg1 | Hetzner nbg1 |

---

## GitHub Actions CI/CD

Automated deployments are configured via GitHub Actions. Tests run before every deployment.

### Workflows

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ci.yml` | PRs, push to `main` | Runs Brakeman, importmap audit, RuboCop, and tests |
| `deploy-production.yml` | Push to `main` | Runs tests, then deploys to production |
| `deploy-staging.yml` | Push to `develop` | Runs tests, deploys to staging, auto-stops after 15 min |
| `staging-control.yml` | Manual | Start/stop/restart staging server |

### Standard Deployment Flow

```
feature branch → PR to develop → merge → staging deploys (auto-stops in 15 min)
                      ↓
              test on staging
                      ↓
              PR to main → merge → production deploys
```

### Staging Auto-Stop Behavior

To conserve database connections (shared DigitalOcean PostgreSQL), staging automatically stops 15 minutes after deployment.

**To keep staging running indefinitely:**
1. Go to Actions → Deploy Staging
2. Click "Run workflow"
3. Select `keep_running: true`
4. Click "Run workflow"

**To manually control staging:**
1. Go to Actions → Staging Control
2. Click "Run workflow"
3. Select action: `start`, `stop`, or `restart`

### Required GitHub Secrets

Set these in repository Settings → Secrets and variables → Actions:

| Secret | Description |
|--------|-------------|
| `SSH_PRIVATE_KEY` | Private SSH key for server access (contents of `~/.ssh/id_ed25519`) |
| `GHCR_TOKEN` | GitHub Container Registry token (use `gh auth token`) |
| `RAILS_MASTER_KEY` | Rails credentials encryption key |
| `STAGING_DATABASE_URL` | Staging PostgreSQL connection string |
| `PRODUCTION_DATABASE_URL` | Production PostgreSQL connection string |
| `ANTHROPIC_API_KEY` | Claude API key |
| `TAVILY_API_KEY` | Tavily search API key |
| `RESEND_API_KEY` | Resend email API key |
| `STAGING_RESEND_WEBHOOK_SECRET` | Staging webhook signing secret |
| `PRODUCTION_RESEND_WEBHOOK_SECRET` | Production webhook signing secret |
| `HETZNER_STORAGE_ACCESS_KEY_ID` | Object storage access key |
| `HETZNER_STORAGE_SECRET_ACCESS_KEY` | Object storage secret key |
| `SCRAPINGBEE_API_KEY` | ScrapingBee API key (optional) |

### SSH Key Setup

**Important:** The `SSH_PRIVATE_KEY` secret must contain the **private** key, not the public key.

```bash
# View your private key (copy entire contents including BEGIN/END lines)
cat ~/.ssh/id_ed25519

# This is WRONG - do not use the .pub file
cat ~/.ssh/id_ed25519.pub  # ❌ This is the public key
```

The corresponding public key must be in the server's `~/.ssh/authorized_keys` file.

### Local Deployments (Manual)

You can still deploy manually using Kamal from your local machine:

```bash
# Deploy to staging
kamal deploy -d staging

# Deploy to production
kamal deploy -d production
```

Local deployments require `.kamal/secrets.staging` and `.kamal/secrets.production` files.

---

## Deployment Commands Reference

### Regular Deployments (Local)

```bash
# ALWAYS commit first!
git add -A && git commit -m "Description of changes"

# Deploy to staging (test first!)
kamal deploy -d staging

# Deploy to production (after staging verified)
kamal deploy -d production

# Deploy specific version
kamal deploy -d production --version=abc123
```

### Maintenance Commands

```bash
# View logs (live)
kamal logs -d production
kamal logs -d staging

# Rails console
kamal console -d production

# Run migrations manually
kamal app exec -d production "bin/rails db:migrate"

# Execute arbitrary command
kamal app exec -d staging "bin/rails runner 'puts User.count'"

# Bash shell
kamal shell -d production
```

### Troubleshooting Commands

```bash
# Check configuration
kamal config
kamal config -d staging

# Check app status
kamal app details -d production

# Restart app
kamal app boot -d production

# Rollback to previous version
kamal rollback -d production

# View proxy logs
kamal proxy logs -d production

# Release stuck deploy lock
kamal lock release -d staging
```

### Database Connection Debugging

```bash
# Check active connections via Rails console
kamal console -d staging
# Then run:
ActiveRecord::Base.connection_pool.stat
# Returns: {size: 5, connections: 2, busy: 1, dead: 0, idle: 1, waiting: 0, checkout_timeout: 5}

# Check PostgreSQL connections directly (via psql or DB console)
SELECT count(*) FROM pg_stat_activity WHERE datname = 'tariffik_staging';

# Terminate all connections (emergency)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'tariffik_staging'
AND pid <> pg_backend_pid();
```

---

## Cost Breakdown

### Current Architecture

| Component | Spec | Cost/month |
|-----------|------|------------|
| Production Server | Hetzner CPX32 (4 vCPU, 8GB RAM) | ~$8 |
| Staging Server | Hetzner CPX22 (2 vCPU, 4GB RAM) | ~$5 |
| PostgreSQL | DigitalOcean Managed (basic) | ~$15 |
| Object Storage | Hetzner (pay per use) | ~$1-2 |
| **Total** | | **~$29-30/month** |

### Previous Render Costs

| Component | Cost/month |
|-----------|------------|
| Production (web + worker + DB) | ~$52 |
| Staging (web + DB) | ~$14-22 |
| **Total** | **~$66-74/month** |

**Savings: ~$40/month (55%)**

---

## Environment Variables Reference

### Required Secrets (in .kamal/secrets)

| Variable | Description |
|----------|-------------|
| `RAILS_MASTER_KEY` | Rails credentials encryption key |
| `DATABASE_URL` | PostgreSQL connection string |
| `ANTHROPIC_API_KEY` | Claude API for commodity suggestions |
| `RESEND_API_KEY` | Resend API for emails |
| `RESEND_WEBHOOK_SECRET` | Webhook signature verification |
| `HETZNER_STORAGE_ACCESS_KEY_ID` | Object storage access key |
| `HETZNER_STORAGE_SECRET_ACCESS_KEY` | Object storage secret key |
| `TAVILY_API_KEY` | Tavily search API (optional) |
| `SCRAPINGBEE_API_KEY` | ScrapingBee fallback (optional) |

### Clear (Non-Secret) Variables

| Variable | Value | Notes |
|----------|-------|-------|
| `RAILS_ENV` | production | Always production, even for staging |
| `WEB_CONCURRENCY` | 0 | Single-mode Puma |
| `RAILS_MAX_THREADS` | 5 | Threads per Puma process |
| `SOLID_QUEUE_IN_PUMA` | true | Run background jobs in web process |
| `RAILS_LOG_TO_STDOUT` | true | Container logging |
| `RAILS_SERVE_STATIC_FILES` | true | Serve assets from Rails |
| `APP_HOST` | tariffik.com | Domain for URL generation |
| `INBOUND_EMAIL_DOMAIN` | inbound.tariffik.com | Email forwarding domain |
| `HETZNER_STORAGE_BUCKET` | tariffik | Object storage bucket name |
| `HETZNER_STORAGE_REGION` | nbg1 | Nuremberg region |
| `HETZNER_STORAGE_ENDPOINT` | https://nbg1.your-objectstorage.com | S3-compatible endpoint |

---

## Troubleshooting Guide

### "remaining connection slots are reserved"

**Cause:** Database connection exhaustion.

**Immediate Fix:**
1. SSH to server or use kamal console
2. Terminate idle connections (see commands above)
3. Restart the app: `kamal app boot -d staging`

**Permanent Fix:**
- Ensure `WEB_CONCURRENCY=0` in deployment config
- Ensure database.yml has `idle_timeout` and `reaping_frequency`
- Verify pool sizes don't exceed database limits

### "Solid Queue is configured to use 5 threads but pool is X"

**Cause:** Queue database pool size is too low.

**Fix:** In `config/database.yml`, ensure queue pool is at least 5:
```yaml
queue:
  <<: *production_primary
  pool: 5  # Must be 5 or higher
```

### "MiniMagick::Error - executable not found: convert"

**Cause:** Using mini_magick but only vips is installed.

**Fix:** In `config/application.rb`:
```ruby
config.active_storage.variant_processor = :vips
```

### Broken image variants

**Debug Steps:**
1. Check blob exists: `ProductLookup.last.product_image.blob`
2. Try downloading: `ProductLookup.last.product_image.blob.download`
3. Check variant URL directly in browser - look at actual error
4. Verify `variant_processor` setting

### Deploy says "ignoring uncommitted changes"

**Cause:** Kamal builds from git, not working directory.

**Fix:** Commit all changes first:
```bash
git add -A && git commit -m "Message"
```

### Deploy lock stuck

**Fix:**
```bash
kamal lock release -d staging
```

### SSL certificate not working

**Fix:**
```bash
kamal proxy reboot -d staging
```
Kamal-proxy will automatically request a new Let's Encrypt certificate.

---

## Security Considerations

### Server Hardening

After initial deployment:

```bash
ssh root@<IP>

# Disable password auth
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Enable firewall
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP (redirect)
ufw allow 443/tcp  # HTTPS
ufw enable

# Auto security updates
apt install unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### Secrets Management

- Never commit `.kamal/secrets` or `.kamal/secrets.staging` to git
- Both files are in `.gitignore`
- Use `gh auth token` for registry password (rotates automatically)
- Rotate API keys periodically

### Database Security

- All connections use SSL (`sslmode=require` in DATABASE_URL)
- DigitalOcean managed PostgreSQL is not publicly accessible by default
- Consider IP allowlisting in DigitalOcean console

---

## Future Improvements

- [ ] Set up external monitoring (UptimeRobot, Better Uptime)
- [ ] Configure error tracking (Sentry, Honeybadger)
- [ ] Add log aggregation (Papertrail, Logtail)
- [ ] Consider connection pooler (PgBouncer) if scaling up
- [ ] Set up database backup exports to external storage
- [ ] Consider CDN for static assets (Cloudflare)
