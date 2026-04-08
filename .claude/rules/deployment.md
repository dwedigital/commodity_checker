---
paths:
  - ".github/**"
  - ".kamal/**"
  - "config/deploy*"
  - "config/recurring*"
  - "Dockerfile*"
  - "Procfile*"
---

# Git Branching & Deployment

**IMPORTANT**: This app uses a feature branch → develop → production workflow with GitHub Actions CI/CD.

## Infrastructure

| Environment | URL | Server | Deploys From |
|-------------|-----|--------|--------------|
| Production | https://tariffik.com | Hetzner VPS (116.203.77.140) | `main` branch |
| Staging | https://staging.tariffik.com | Hetzner VPS (91.99.171.192) | `develop` branch |

See `claude/implementations/hetzner-infrastructure-deployment.md` for full docs.

## GitHub Actions Workflows

| Workflow | File | Trigger | What It Does |
|----------|------|---------|--------------|
| CI | `ci.yml` | PRs, push to `main` | Security scans, linting, tests |
| Deploy Production | `deploy-production.yml` | Push to `main` | Tests + deploy to production |
| Deploy Staging | `deploy-staging.yml` | Push to `develop` | Tests + deploy, **auto-stops after 15 min** |
| Staging Control | `staging-control.yml` | Manual | Start/stop/restart staging |

### Staging Auto-Stop

Staging stops 15 min after deployment to conserve DB connections. To keep running: Actions → Deploy Staging → `keep_running: true`. Manual control: Actions → Staging Control.

## Branches

- `feature/*`, `bugfix/*`, `hotfix/*` → Development branches
- `develop` → Auto-deploys to staging
- `main` → Auto-deploys to production

## Standard Workflow

```bash
git checkout develop && git pull origin develop
git checkout -b feature/my-new-feature
# Make changes, commit, push
git push -u origin feature/my-new-feature
gh pr create --base develop --title "Feature: My new feature"
gh pr merge --merge
# Test on staging, then:
gh pr create --base main --head develop --title "Release: Description"
gh pr merge --merge
```

## Hotfix Workflow

```bash
git checkout main && git pull origin main
git checkout -b hotfix/fix-critical-bug
# Fix, commit, push, PR to main, merge
git checkout develop && git merge main && git push origin develop
```

## Manual Deployments (Kamal)

```bash
kamal deploy -d staging      # Deploy to staging
kamal deploy -d production   # Deploy to production
```

Requires `.kamal/secrets.staging` and `.kamal/secrets.production` locally.

## Production Configuration

Puma auto-detects workers from RAM (reserves 512MB system, 512MB per worker, max 8). Override with `WEB_CONCURRENCY`. Runs with `preload_app!` for copy-on-write savings.

## Never

- Commit directly to `main` or `develop`
- Force push to `main`
- Deploy untested code to production
- Merge to `main` without testing on staging first
