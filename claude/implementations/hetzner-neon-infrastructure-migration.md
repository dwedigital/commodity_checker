# Hetzner + Neon Infrastructure Migration

**Date:** 2026-01-20
**Feature:** Migration from Render to Hetzner VPS + Neon PostgreSQL

## Overview

This implementation migrates Tariffik's hosting infrastructure from Render (PaaS) to a self-managed setup using:
- **Hetzner Cloud VPS** - Two separate servers for production and staging in Helsinki
- **Neon PostgreSQL** - Serverless PostgreSQL with database branching in Frankfurt
- **Kamal 2** - Rails' official deployment tool for Docker-based deployments
- **GitHub Container Registry (ghcr.io)** - Docker image hosting

### Why This Migration?

| Aspect | Render (Before) | Hetzner + Neon (After) |
|--------|-----------------|------------------------|
| Monthly Cost | ~$66-74 | ~$15.50 |
| Control | Limited | Full root access |
| Database | Managed PostgreSQL | Serverless PostgreSQL with branching |
| Deployment | Git push | Kamal (Docker) |
| SSL | Automatic | Automatic (Let's Encrypt via kamal-proxy) |
| Scaling | PaaS limits | Full control |

**Savings: ~$55/month (78%)**

---

## Architecture

```
                          +-------------------------------------+
                          |         Neon PostgreSQL             |
                          |  (Serverless, Frankfurt)            |
                          +-------------------------------------+
                          |  production (main branch)           |
                          |         |                           |
                          |         +-- staging (branch)        |
                          |             (copy-on-write)         |
                          +-----------------+-------------------+
                                            |
                    +-----------------------+------------------------+
                    |                                                |
                    v                                                v
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
|  |  - Thruster (compression) ||          |  |  - Thruster (compression) ||
|  +---------------------------+|          |  +---------------------------+|
|                               |          |                               |
|  tariffik.com                 |          |  staging.tariffik.com         |
|  Let's Encrypt SSL            |          |  Let's Encrypt SSL            |
+-------------------------------+          +-------------------------------+
```

---

## Configuration Summary

| Setting | Value |
|---------|-------|
| GitHub Username | `dwedigital` |
| Container Registry | `ghcr.io/dwedigital/tariffik` |
| Production Domain | `tariffik.com` |
| Staging Domain | `staging.tariffik.com` |
| Hetzner Region | Helsinki (hel1) |
| Neon Region | Frankfurt (eu-central-1) |
| Production Server | CPX32 (4 vCPU, 8GB RAM) |
| Staging Server | CPX22 (2 vCPU, 4GB RAM) |

---

## Cost Breakdown

### New Architecture (Hetzner Helsinki + Neon Frankfurt)

| Component | Spec | Cost/month |
|-----------|------|------------|
| Production Server | Hetzner CPX32 (4 vCPU, 8GB RAM) x86/AMD | ~$8 |
| Staging Server | Hetzner CPX22 (2 vCPU, 4GB RAM) x86/AMD | ~$5 |
| Neon PostgreSQL | Free tier (0.5GB, 190 compute hrs) | $0 |
| Server Backups | Hetzner automated (20% of server) | ~$2.50 |
| **Total** | | **~$15.50/month** |

### Previous Render Costs

| Component | Cost/month |
|-----------|------------|
| Production (web + worker + DB) | ~$52 |
| Staging (web + DB) | ~$14-22 |
| **Total** | **~$66-74/month** |

---

## Design Decisions

### Why Two Separate Servers?
- **Complete isolation** - Staging issues can't affect production
- **Independent scaling** - Size each server appropriately
- **Simpler networking** - No container orchestration needed
- **Cost-effective** - Small staging server uses minimal resources

### Why Neon PostgreSQL?
1. **Database Branching** - Staging uses a copy-on-write branch of production
   - Instant creation, no data sync needed
   - Changes to staging don't affect production
   - Can reset staging to production state anytime
2. **Serverless** - Scales to zero when not in use
3. **Auto-backups** - Point-in-time recovery included (7-day history on free tier)
4. **Low Latency** - Frankfurt region ~10ms from Helsinki

### Why Helsinki for Servers?
- UK-focused app benefits from EU proximity
- Frankfurt (Neon) to Helsinki latency: ~10ms
- Helsinki CPX servers: Best price-to-performance ratio
- Alternative: Falkenstein (Germany) if lower DB latency preferred

### Why x86/AMD (CPX) Instead of ARM (CAX)?
- Existing Dockerfile builds for `amd64`
- Wider compatibility with Docker images
- Simpler debugging (native on most dev machines)
- CAX would require rebuilding for `arm64`

---

## Pre-Implementation Checklist

Before deploying, ensure you have:

- [ ] Hetzner Cloud account created
- [ ] GitHub Personal Access Token with `write:packages` and `read:packages` scope
- [ ] Neon account created (free at neon.tech)
- [ ] DNS access for tariffik.com (to add A records)
- [ ] Current Render environment variables documented
- [ ] SSH key pair for server access

---

## New Files Created

| File | Purpose |
|------|---------|
| `.kamal/secrets.staging` | Staging-specific secrets (DATABASE_URL override) |
| `claude/implementations/hetzner-neon-infrastructure-migration.md` | This documentation |

---

## Modified Files

| File | Change |
|------|--------|
| `Dockerfile` | Added `libpq-dev` (build) and `libpq5` (runtime) for PostgreSQL |
| `config/deploy.yml` | Complete rewrite for multi-destination deployment |
| `.kamal/secrets` | Added all production environment variables |

---

## File Changes in Detail

### Dockerfile Changes

Added PostgreSQL client libraries:

```dockerfile
# Base stage - runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl libjemalloc2 libvips sqlite3 libpq5 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Build stage - compile-time dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential git libyaml-dev pkg-config libpq-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

### config/deploy.yml (Complete Rewrite)

```yaml
service: tariffik
image: ghcr.io/dwedigital/tariffik

# Shared proxy configuration
proxy:
  ssl: true

# GitHub Container Registry
registry:
  server: ghcr.io
  username: dwedigital
  password:
    - KAMAL_REGISTRY_PASSWORD

# Build for x86/AMD (Hetzner CPX servers)
builder:
  arch: amd64

# Environment variables (shared across all destinations)
env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - ANTHROPIC_API_KEY
    - TAVILY_API_KEY
    - RESEND_API_KEY
    - RESEND_WEBHOOK_SECRET
    - CLOUDFLARE_R2_ACCESS_KEY_ID
    - CLOUDFLARE_R2_SECRET_ACCESS_KEY
    - SCRAPINGBEE_API_KEY
  clear:
    SOLID_QUEUE_IN_PUMA: true
    RAILS_LOG_TO_STDOUT: true
    RAILS_SERVE_STATIC_FILES: true
    CLOUDFLARE_R2_BUCKET: tariffik-images
    CLOUDFLARE_R2_ENDPOINT: https://<account-id>.r2.cloudflarestorage.com

# Kamal aliases
aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell: app exec --interactive --reuse "bash"
  logs: app logs -f
  dbc: app exec --interactive --reuse "bin/rails dbconsole"

# Default servers (production)
servers:
  web:
    hosts:
      - <PRODUCTION_IP>

# ============ PRODUCTION DESTINATION ============
destinations:
  production:
    hosts:
      - <PRODUCTION_IP>
    proxy:
      host: tariffik.com
    env:
      clear:
        RAILS_ENV: production
        APP_HOST: tariffik.com
        INBOUND_EMAIL_DOMAIN: inbound.tariffik.com

  # ============ STAGING DESTINATION ============
  staging:
    hosts:
      - <STAGING_IP>
    proxy:
      host: staging.tariffik.com
    env:
      clear:
        RAILS_ENV: production
        APP_HOST: staging.tariffik.com
        INBOUND_EMAIL_DOMAIN: inbound.staging.tariffik.com
```

### .kamal/secrets (Production)

```bash
# GitHub Container Registry token
KAMAL_REGISTRY_PASSWORD=$(gh auth token)

# Rails master key (never commit config/master.key!)
RAILS_MASTER_KEY=$(cat config/master.key)

# Neon PostgreSQL connection (production)
DATABASE_URL=postgresql://user:password@ep-xxx.eu-central-1.aws.neon.tech/tariffik_production?sslmode=require

# AI Services
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
TAVILY_API_KEY=$TAVILY_API_KEY

# Email (Resend)
RESEND_API_KEY=$RESEND_API_KEY
RESEND_WEBHOOK_SECRET=$RESEND_WEBHOOK_SECRET

# Cloudflare R2 Storage
CLOUDFLARE_R2_ACCESS_KEY_ID=$CLOUDFLARE_R2_ACCESS_KEY_ID
CLOUDFLARE_R2_SECRET_ACCESS_KEY=$CLOUDFLARE_R2_SECRET_ACCESS_KEY

# Web Scraping (optional)
SCRAPINGBEE_API_KEY=$SCRAPINGBEE_API_KEY
```

### .kamal/secrets.staging

```bash
# Inherit from main secrets
source .kamal/secrets

# Override DATABASE_URL for staging branch
DATABASE_URL=postgresql://user:password@ep-xxx.eu-central-1.aws.neon.tech/tariffik_staging?sslmode=require
```

---

## Implementation Steps

### Phase 1: Neon PostgreSQL Setup

1. **Create Neon account** at https://neon.tech (free tier)
2. **Create new project** named "tariffik"
3. **Select Frankfurt region** (eu-central-1) - closest to Helsinki
4. **Note the connection string** for the main branch (production)
5. **Create a branch** named "staging" from production
6. **Note the staging connection string** (will have different endpoint)

Connection strings will look like:
```
postgresql://user:password@ep-xxx-yyy.eu-central-1.aws.neon.tech/neondb?sslmode=require
```

### Phase 2: Hetzner Server Setup

1. **Create Hetzner Cloud account** at https://console.hetzner.cloud
2. **Create SSH key** (if not already done):
   ```bash
   ssh-keygen -t ed25519 -C "tariffik-deploy"
   ```
3. **Add SSH key to Hetzner** in Cloud Console → Security → SSH Keys
4. **Create Production Server**:
   - Name: `tariffik-production`
   - Location: Helsinki (hel1)
   - Type: CPX32 (4 vCPU, 8GB RAM, AMD)
   - Image: Ubuntu 24.04
   - SSH Key: Select your key
   - Enable backups (optional but recommended)
5. **Create Staging Server**:
   - Name: `tariffik-staging`
   - Location: Helsinki (hel1)
   - Type: CPX22 (2 vCPU, 4GB RAM, AMD)
   - Image: Ubuntu 24.04
   - SSH Key: Select your key
6. **Note both IP addresses**

### Phase 3: GitHub Container Registry Setup

1. **Create Personal Access Token**:
   - Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - Or use classic token with `write:packages` and `read:packages` scopes
2. **Verify gh CLI is authenticated**:
   ```bash
   gh auth token  # Should output a token
   ```

### Phase 4: DNS Configuration

1. **Update tariffik.com A record** → Production server IP
2. **Create staging.tariffik.com A record** → Staging server IP
3. **Update inbound email records** if needed:
   - `inbound.tariffik.com` MX record (for production emails)
   - `inbound.staging.tariffik.com` MX record (optional, for staging emails)
4. **Wait for DNS propagation** (can check with `dig tariffik.com`)

### Phase 5: Update Configuration Files

Replace placeholders in configuration files:

```bash
# In config/deploy.yml, replace:
<PRODUCTION_IP>   → Your production server IP (e.g., 95.216.xxx.xxx)
<STAGING_IP>      → Your staging server IP (e.g., 95.216.yyy.yyy)

# In .kamal/secrets, replace:
DATABASE_URL      → Your Neon production connection string

# In .kamal/secrets.staging, replace:
DATABASE_URL      → Your Neon staging branch connection string
```

### Phase 6: Initial Deployment

```bash
# Verify configuration
kamal config

# Deploy to production (first time setup)
kamal setup -d production

# Deploy to staging (first time setup)
kamal setup -d staging

# For subsequent deployments
kamal deploy -d production
kamal deploy -d staging
```

### Phase 7: Migrate Data (If Needed)

If you need to migrate existing data from Render:

```bash
# On Render, create a backup
pg_dump DATABASE_URL > tariffik_backup.sql

# Upload to Neon using psql or Neon console
psql "postgresql://user:pass@ep-xxx.neon.tech/neondb?sslmode=require" < tariffik_backup.sql
```

### Phase 8: Update Resend Webhooks

1. Go to Resend dashboard
2. Update inbound email webhook URL to new server
3. Verify webhook signature secret matches

### Phase 9: Verification & Monitoring

Run through the verification checklist below.

### Phase 10: Render Teardown (After 1-2 Weeks)

Only after confirming Hetzner deployment is stable:
1. Cancel Render web services
2. Delete Render databases (after final backup)
3. Remove any Render-specific configuration

---

## Deployment Commands Reference

### Regular Deployments

```bash
# Deploy to production
kamal deploy -d production

# Deploy to staging
kamal deploy -d staging

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
```

### Server Management

```bash
# SSH directly to server
ssh root@<PRODUCTION_IP>
ssh root@<STAGING_IP>

# View Docker containers
kamal app exec -d production "docker ps"

# Check disk space
kamal app exec -d production "df -h"

# Check memory
kamal app exec -d production "free -m"
```

---

## Verification Checklist

After deployment, verify each item:

### Production Verification
- [ ] https://tariffik.com loads correctly (SSL valid)
- [ ] Can log in with existing account
- [ ] Dashboard shows existing orders
- [ ] Commodity code lookup works (test with "cotton t-shirt")
- [ ] New user registration works
- [ ] Inbound email processing works (forward a test email)
- [ ] Background jobs process (check Solid Queue)
- [ ] Images upload to R2 and display correctly
- [ ] Photo lookup feature works (camera/upload)

### Staging Verification
- [ ] https://staging.tariffik.com loads correctly (SSL valid)
- [ ] Can log in (staging uses production DB branch, so same users)
- [ ] All features work as production

### Database Verification
- [ ] Neon dashboard shows active connections
- [ ] Database metrics are normal
- [ ] Staging branch shows in Neon branches list

### Performance Verification
- [ ] Page load time < 2s
- [ ] Background jobs process within expected time
- [ ] No connection timeouts to Neon

---

## Rollback Plan

If the migration fails at any point:

1. **DNS Rollback**: Point A records back to Render
2. **Render Services**: Should still be running (don't delete yet)
3. **Database**: Render PostgreSQL still has latest data
4. **Debug**: Review logs on Hetzner to identify issues

Only delete Render services after 1-2 weeks of stable Hetzner operation.

---

## Monitoring & Maintenance

### Neon Dashboard
- Monitor compute hours usage (free tier: 190 hrs/month)
- Check storage usage (free tier: 0.5GB)
- View query performance metrics

### Hetzner Console
- Monitor CPU/memory usage
- Check backup status
- Review network traffic

### Application Monitoring
- Rails logs: `kamal logs -d production`
- Solid Queue: Check `/admin/solid_queue` (if enabled)
- PgHero: Check `/admin/pghero` for slow queries

### Backup Strategy
- **Neon**: Automatic point-in-time recovery (7 days on free tier)
- **Hetzner**: Enable automated backups (~20% extra cost)
- **Manual**: Periodic `pg_dump` exports stored off-server

---

## Troubleshooting

### "Connection refused" to Neon
```bash
# Check if server can reach Neon
kamal app exec -d production "ping ep-xxx.eu-central-1.aws.neon.tech"

# Verify DATABASE_URL is set correctly
kamal app exec -d production "echo \$DATABASE_URL"
```

### SSL Certificate Issues
```bash
# Check proxy status
kamal proxy details -d production

# Force certificate renewal
kamal proxy reboot -d production
```

### Container Won't Start
```bash
# Check Docker logs
kamal app logs -d production

# Check for crash loop
kamal app details -d production

# Try manual start
kamal app boot -d production
```

### Slow Database Queries
```bash
# Access PgHero dashboard
open https://tariffik.com/admin/pghero

# Or check via console
kamal console -d production
# Then: PgHero.slow_queries
```

---

## Neon-Specific Operations

### Reset Staging to Production

When you want staging to have fresh production data:

```bash
# In Neon Console:
# 1. Delete staging branch
# 2. Create new branch from production

# Or via Neon CLI:
neon branches delete staging --project-id <id>
neon branches create --name staging --project-id <id>
```

### Point-in-Time Recovery

If you need to recover data:
1. Go to Neon Console → Branches → Production
2. Click "Restore" and select a timestamp
3. Creates a new branch at that point in time
4. Migrate data as needed

---

## Security Considerations

### Server Hardening (Recommended)

After initial deployment, consider:

```bash
# SSH to server
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
- Never commit `.kamal/secrets` to git (already in .gitignore)
- Use `gh auth token` for registry password (rotates automatically)
- Consider 1Password/Vault for team environments

### Database Security
- Neon connections require SSL (`sslmode=require`)
- IP allowlisting available on paid Neon plans
- Connection pooling via Neon's built-in pooler

---

## Future Improvements

- [ ] Set up external monitoring (UptimeRobot, Better Uptime)
- [ ] Configure error tracking (Sentry, Honeybadger)
- [ ] Add log aggregation (Papertrail, Logtail)
- [ ] Implement zero-downtime deployments (already supported by Kamal)
- [ ] Consider CDN for static assets (Cloudflare)
- [ ] Set up staging-specific Resend domain for email testing

---

## Appendix: Environment Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `RAILS_MASTER_KEY` | Rails credentials encryption key | `abc123...` |
| `DATABASE_URL` | Neon PostgreSQL connection string | `postgresql://user:pass@ep-xxx.neon.tech/db` |
| `ANTHROPIC_API_KEY` | Claude API for commodity suggestions | `sk-ant-...` |
| `RESEND_API_KEY` | Resend API for emails | `re_...` |
| `RESEND_WEBHOOK_SECRET` | Webhook signature verification | `whsec_...` |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 storage access key | `abc...` |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 storage secret key | `xyz...` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TAVILY_API_KEY` | Tavily search API | - |
| `SCRAPINGBEE_API_KEY` | ScrapingBee fallback | - |
| `WEB_CONCURRENCY` | Puma workers | Auto-detected |
| `RAILS_MAX_THREADS` | Threads per worker | 3 |

### Clear (Non-Secret) Variables

| Variable | Production | Staging |
|----------|------------|---------|
| `RAILS_ENV` | production | production |
| `APP_HOST` | tariffik.com | staging.tariffik.com |
| `INBOUND_EMAIL_DOMAIN` | inbound.tariffik.com | inbound.staging.tariffik.com |
| `SOLID_QUEUE_IN_PUMA` | true | true |
| `RAILS_LOG_TO_STDOUT` | true | true |
| `RAILS_SERVE_STATIC_FILES` | true | true |
