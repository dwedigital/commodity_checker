# Lograge and PgHero Admin Implementation

**Date:** 2026-01-19
**Feature:** Structured logging via Lograge and PostgreSQL monitoring via PgHero with admin-only access

## Overview

This implementation adds two operational improvements to Tariffik:

1. **Lograge** - Replaces verbose multi-line Rails logs with single-line structured JSON-style output, including user ID, IP address, and request ID for better log analysis
2. **PgHero** - PostgreSQL monitoring dashboard for production database insights, query analysis, and index suggestions
3. **Admin Role** - Simple boolean admin flag on users to protect PgHero dashboard access

## Design Decisions

- **Simple admin flag**: A boolean `admin` column is sufficient for this use case - no complex role/permission system needed
- **Devise authentication**: PgHero routes use Devise's `authenticate` constraint with a custom lambda to check admin status
- **Lograge custom payload**: Adds user_id, IP, and request_id to every log line for debugging and audit trails
- **PgHero path**: Mounted at `/admin/pghero` to clearly indicate admin-only area

## Database Changes

### Modified Table: `users`

```ruby
add_column :users, :admin, :boolean, default: false, null: false
add_index :users, :admin
```

## New Files Created

### Initializers

| File | Purpose |
|------|---------|
| `config/initializers/lograge.rb` | Lograge configuration with custom payload options (user_id, IP, request_id) |

### Migrations

| File | Purpose |
|------|---------|
| `db/migrate/20260119093854_add_admin_to_users.rb` | Adds admin boolean column with default false and index |

## Modified Files

### Gemfile

| Change |
|--------|
| Added `gem "lograge"` for structured logging |
| Added `gem "pghero"` for PostgreSQL monitoring |
| Added `gem "pg_query", ">= 2"` for PgHero index suggestions |

### Models

| File | Change |
|------|--------|
| `app/models/user.rb` | Added `admin?` method that returns `admin == true` |

### Controllers

| File | Change |
|------|--------|
| `app/controllers/application_controller.rb` | Added `append_info_to_payload` method to add user_id, IP, and request_id to Lograge logs |

### Routes

| File | Change |
|------|--------|
| `config/routes.rb` | Added admin-only authenticated route for PgHero at `/admin/pghero` (production only) |

## Routes

```
/admin/pghero/*  → PgHero::Engine (production only, admin-only, requires Devise authentication + admin? check)
```

**Note:** PgHero routes are only mounted in production (`Rails.env.production?`) because PgHero requires PostgreSQL, and the app uses SQLite in development.

## Data Flow

### Lograge Request Logging

```
HTTP Request arrives
        │
        ▼
ApplicationController processes request
        │
        ├─── append_info_to_payload adds:
        │       - user_id (from current_user)
        │       - ip (from request.remote_ip)
        │       - request_id (from request.request_id)
        │
        ▼
Response sent
        │
        ▼
Lograge outputs single-line structured log:
  method=GET path=/dashboard format=html controller=DashboardController
  action=index status=200 duration=45.2 time=2026-01-19T09:00:00Z
  user_id=123 request_id=abc-123 ip=192.168.1.1
```

### PgHero Admin Access

```
User visits /admin/pghero
        │
        ▼
Devise authenticate constraint
        │
        ├─── Not logged in? → Redirect to sign_in
        │
        └─── Logged in → Check user.admin?
                │
                ├─── admin? == false → 404 Not Found
                │
                └─── admin? == true → PgHero Dashboard
```

## Testing

### Manual Testing Steps

1. **Lograge**: Make any request and check logs - should see single-line structured output
2. **Admin field**: `rails console` → `User.first.update(admin: true)` → verify `user.admin?` returns true
3. **PgHero non-admin**: Sign in as non-admin user, visit `/admin/pghero` → should get 404
4. **PgHero admin**: Sign in as admin user, visit `/admin/pghero` → should see PgHero dashboard

### Verification Commands

```bash
# Check Lograge is enabled
bin/rails runner "puts Rails.application.config.lograge.enabled"

# Test admin method
bin/rails runner "
  user = User.first
  puts 'Admin status: ' + user.admin?.to_s
  user.update(admin: true)
  puts 'After update: ' + user.admin?.to_s
"

# Check routes
bin/rails routes | grep pghero

# Verify PgHero is mounted
bin/rails runner "puts PgHero::Engine.routes.routes.map(&:path).join('\n')"
```

## Limitations & Future Improvements

### Current Limitations

- **Production-only PgHero**: PgHero routes are only mounted in production because PgHero requires PostgreSQL and the app uses SQLite in development. To test PgHero locally, you would need to configure a local PostgreSQL database.
- **Simple admin flag**: No granular permissions - users are either admin or not

### Potential Future Improvements

1. **Admin dashboard index**: Create an `/admin` landing page with links to PgHero and other admin tools
2. **Role-based access**: If more granular permissions are needed, consider adding a `role` enum or separate roles table
3. **Lograge JSON formatter**: Configure `config.lograge.formatter = Lograge::Formatters::Json.new` for pure JSON output suitable for log aggregation services
4. **PgHero scheduled checks**: Set up background jobs for automated slow query detection and alerts

## Files Summary

### New Files (2)
- `config/initializers/lograge.rb`
- `db/migrate/20260119093854_add_admin_to_users.rb`

### Modified Files (4)
- `Gemfile`
- `app/models/user.rb`
- `app/controllers/application_controller.rb`
- `config/routes.rb`
