# Implementation: Recurring Jobs & Admin Dashboard

## Overview

Added recurring background job infrastructure using Solid Queue's built-in scheduler, plus an admin dashboard for monitoring jobs. Includes a cleanup job that removes orphaned inbound emails after a grace period.

## Design Decisions

### Why Solid Queue Recurring Jobs?

Rails 8 ships with Solid Queue which has native support for recurring jobs via `config/recurring.yml`. This eliminates the need for external schedulers like cron or gems like `whenever`/`clockwork`.

### Orphaned Email Cleanup Strategy

When an order is destroyed, associated `inbound_emails` have their `order_id` set to NULL (via `dependent: :nullify`) rather than being deleted. This provides:

1. **Recovery window** - If an order is deleted by mistake, emails can be re-processed
2. **Audit trail** - Email content preserved for debugging
3. **Eventual cleanup** - Job deletes orphans after 30 days (7 days on staging)

### Admin Dashboard Authentication

Used Devise's `authenticate` constraint rather than Mission Control's built-in HTTP Basic auth. This provides:
- Single sign-on with existing admin accounts
- Consistent auth experience across admin tools (PgHero, Solid Queue)
- No additional credentials to manage

## Database Changes

None. Uses existing Solid Queue tables.

## New Files Created

| File | Purpose |
|------|---------|
| `app/jobs/cleanup_orphaned_emails_job.rb` | Deletes orphaned inbound emails older than N days |
| `config/initializers/mission_control.rb` | Disables HTTP Basic auth (using Devise instead) |
| `test/jobs/cleanup_orphaned_emails_job_test.rb` | Unit tests for cleanup job |

## Modified Files

| File | Changes |
|------|---------|
| `Gemfile` | Added `mission_control-jobs` gem |
| `config/recurring.yml` | Added cleanup job schedule for production/staging |
| `config/routes.rb` | Mounted Mission Control dashboard at `/admin/jobs` |
| `app/jobs/CLAUDE.md` | Documented new job and recurring jobs system |
| `CLAUDE.md` | Added Admin Dashboards section |

## Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/admin/jobs` | Solid Queue dashboard (admin only) |
| GET | `/admin/jobs/*` | Dashboard sub-routes (queues, jobs, recurring) |

## Configuration

### Recurring Jobs (`config/recurring.yml`)

```yaml
production:
  cleanup_orphaned_emails:
    class: CleanupOrphanedEmailsJob
    args: [{ days_old: 30 }]
    schedule: at 3am every day

staging:
  cleanup_orphaned_emails:
    class: CleanupOrphanedEmailsJob
    args: [{ days_old: 7 }]    # Shorter for testing
    schedule: at 3am every day
```

### Mission Control (`config/initializers/mission_control.rb`)

```ruby
Rails.application.configure do
  config.mission_control.jobs.http_basic_auth_enabled = false
end
```

## Data Flow

```
Solid Queue Scheduler (runs continuously)
      │
      ├─ Checks config/recurring.yml
      │
      ├─ At 3am daily:
      │     └─ Enqueues CleanupOrphanedEmailsJob
      │
      └─ Every hour at :12:
            └─ Runs SolidQueue::Job.clear_finished_in_batches

CleanupOrphanedEmailsJob
      │
      └─ DELETE FROM inbound_emails
         WHERE order_id IS NULL
         AND created_at < (now - 30 days)
```

## Testing/Verification

### Run Tests

```bash
bin/rails test test/jobs/cleanup_orphaned_emails_job_test.rb
```

### Manual Testing

```ruby
# In Rails console

# Create test orphaned email
email = InboundEmail.create!(
  user: User.first,
  subject: "Test",
  from_address: "test@example.com",
  order_id: nil,
  created_at: 45.days.ago
)

# Run cleanup
CleanupOrphanedEmailsJob.perform_now(days_old: 30)

# Verify deleted
InboundEmail.exists?(email.id)  # => false
```

### Access Admin Dashboard

1. Log in as admin user (`user.admin? == true`)
2. Navigate to `/admin/jobs`
3. View queues, jobs, and recurring schedules

## Limitations & Future Improvements

### Current Limitations

1. **No holiday awareness** - Jobs run on schedule regardless of holidays
2. **Single timezone** - Schedule uses server timezone (UTC in production)
3. **No alerting** - Failed recurring jobs only visible in dashboard

### Future Improvements

1. Add email alerts for failed jobs
2. Add more cleanup jobs (old tracking events, expired API keys)
3. Add job metrics/graphs to dashboard
4. Consider `good_job` if need more advanced features (cron syntax, job priorities)
