# Ahoy Analytics Implementation

**Date:** 2026-01-17
**Updated:** 2026-01-23
**Feature:** Privacy-first analytics using the Ahoy gem + Admin Dashboard

## Overview

This implementation adds privacy-first analytics to Tariffik using the Ahoy gem. All analytics data is stored in the database (no third-party services), with cookieless mode enabled for GDPR compliance. The system tracks both guest and authenticated user events, automatically associating events with user IDs when users are logged in.

**Why Ahoy:**
- No third-party cookies or tracking pixels
- All data stays in your PostgreSQL database
- Automatic user association for logged-in users
- Standard SQL tables ready for Metabase/Looker
- Native PostgreSQL jsonb support for efficient queries

**2026-01-23 Updates:**
- Added admin analytics dashboard at `/admin/analytics`
- Added sign-up tracking via custom Devise registrations controller
- Added extension lookup tracking (server-side)
- Converted `ahoy_events.properties` from text to jsonb with GIN index
- Added rake tasks for seeding mock analytics data

## Design Decisions

### 1. Same Database
Ahoy tables (`ahoy_visits`, `ahoy_events`) go in the primary database alongside existing tables. The volume of analytics events won't stress the database at this scale.

### 2. Keep `GuestLookup` Model
The existing `GuestLookup` model is tightly coupled to rate-limiting logic (3 free lookups per week). Ahoy handles analytics separately - this separation of concerns is cleaner than trying to repurpose rate-limiting data for analytics.

### 3. Cookieless Mode
Using `Ahoy.cookies = :none` for cookieless visitor identification. Ahoy automatically generates anonymous visitor tokens without storing cookies.

### 4. User ID Association
**Ahoy automatically associates events with users when logged in:**
- `ahoy_visits.user_id` - Links visits to users
- `ahoy_events.user_id` - Links every event to the user who triggered it
- When `current_user` exists, Ahoy captures `user_id` automatically
- Background jobs pass user explicitly: `AnalyticsTracker.new(user: order.user)`

---

## Database Changes

### New Table: `ahoy_visits`

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| visit_token | string | Unique visit identifier |
| visitor_token | string | Anonymous visitor identifier (cookieless) |
| user_id | bigint | **FK to users** (null for guests) |
| referring_domain | string | Traffic source domain |
| referrer | text | Full referrer URL |
| landing_page | text | First page visited |
| browser | string | Browser name |
| os | string | Operating system |
| device_type | string | desktop/mobile/tablet |
| utm_source | string | UTM tracking |
| utm_medium | string | UTM tracking |
| utm_campaign | string | UTM tracking |
| started_at | datetime | Visit start time |

### New Table: `ahoy_events`

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| visit_id | bigint | FK to ahoy_visits |
| user_id | bigint | **FK to users** (null for guests) |
| name | string | Event name (e.g., `order_created`) |
| properties | **jsonb** | Event properties (native PostgreSQL JSON) |
| time | datetime | When event occurred |

**Note:** The `properties` column was migrated from `text` to `jsonb` on 2026-01-23 to enable native PostgreSQL JSON operators (`->>`) for efficient queries.

### Indexes
- `ahoy_visits.visit_token` (unique)
- `ahoy_visits.visitor_token, started_at` (compound)
- `ahoy_events.name, time` (compound)
- `ahoy_events.properties` (GIN index for jsonb queries)

---

## New Files Created

| File | Purpose |
|------|---------|
| `config/initializers/ahoy.rb` | Ahoy configuration (cookieless mode, privacy settings) |
| `app/models/ahoy/visit.rb` | Ahoy Visit model (auto-generated) |
| `app/models/ahoy/event.rb` | Ahoy Event model (jsonb properties, visit optional for server-side events) |
| `app/controllers/concerns/trackable.rb` | Controller concern for tracking events |
| `app/services/analytics_tracker.rb` | Service for tracking events in background jobs |
| `db/migrate/20260117171118_create_ahoy_visits_and_events.rb` | Migration for both tables |
| `app/controllers/admin/analytics_controller.rb` | Admin dashboard with visitor/lookup/signup stats |
| `app/views/admin/analytics/index.html.erb` | Dashboard view with charts and stats cards |
| `app/controllers/users/registrations_controller.rb` | Custom Devise controller for sign-up tracking |
| `app/javascript/controllers/simple_chart_controller.js` | CSP-compliant Canvas-based line charts |
| `lib/tasks/seed_analytics.rake` | Rake tasks to seed/clear mock analytics data |
| `db/migrate/20260123205132_change_ahoy_events_properties_to_jsonb.rb` | Migration to convert properties to jsonb |

---

## Modified Files

| File | Changes |
|------|---------|
| `Gemfile` | Add `ahoy_matey`, `device_detector` gems |
| `app/controllers/application_controller.rb` | Include `Trackable` concern |
| `app/controllers/pages_controller.rb` | Track guest lookup events |
| `app/controllers/product_lookups_controller.rb` | Track user lookup and confirmation events |
| `app/controllers/orders_controller.rb` | Track order creation and confirmation events |
| `app/models/user.rb` | Track account creation via after_create callback |
| `app/jobs/process_inbound_email_job.rb` | Track email forwarding and order creation |
| `app/jobs/suggest_commodity_codes_job.rb` | Track commodity code suggestions |
| `app/controllers/api/v1/extension_controller.rb` | Track extension lookup events (server-side) |
| `config/routes.rb` | Add admin analytics route |
| `config/database.yml` | PostgreSQL by default, SQLite fallback with USE_SQLITE=true |
| `docker-compose.yml` | Local PostgreSQL container (port 5444) |

---

## Events Schema

### Page View Events (all users)

| Event | Properties | Trigger |
|-------|------------|---------|
| `page_view` | `page`, `controller`, `action` | Automatic after_action for all HTML GET requests |

### Guest Events (user_id = NULL)

| Event | Properties | Trigger |
|-------|------------|---------|
| `guest_lookup_performed` | `guest_token`, `lookups_remaining`, `commodity_code` | PagesController#lookup |
| `guest_limit_reached` | `guest_token`, `lookup_count` | PagesController#lookup (when limit hit) |

### User Events (user_id = current_user.id)

| Event | Properties | Trigger |
|-------|------------|---------|
| `user_registered` | `user_id`, `registration_source` | Custom Devise RegistrationsController |
| `user_lookup_performed` | `lookup_id`, `lookup_type`, `commodity_code` | PagesController, ProductLookupsController |
| `extension_lookup_performed` | `user_id`, `commodity_code`, `source` | ExtensionController (server-side) |
| `user_email_forwarded` | `email_id`, `email_type` | ProcessInboundEmailJob |
| `order_created` | `order_id`, `retailer`, `source` | OrdersController, ProcessInboundEmailJob |
| `commodity_code_suggested` | `order_item_id`, `commodity_code`, `confidence` | SuggestCommodityCodesJob |
| `commodity_code_confirmed` | `order_item_id` or `product_lookup_id`, `commodity_code` | OrdersController, ProductLookupsController |

---

## Data Flow

### Controller Event Tracking

```
User action in browser
         │
         ▼
Controller action
         │
         ├─── track_event("event_name", properties)
         │           │
         │           ▼
         │    Trackable#track_event
         │           │
         │           ▼
         │    ahoy.track(name, properties)
         │           │
         │           ▼
         │    Ahoy::Store.track_event
         │           │
         │           ├─── Creates Ahoy::Visit if needed
         │           │
         │           └─── Creates Ahoy::Event with user_id
         │
         ▼
Normal controller response
```

### Background Job / Model Callback Event Tracking

```
Background job or model callback executes
         │
         ▼
AnalyticsTracker.new(user: user).track(...)
         │
         ▼
Ahoy::Event.create!(user_id:, name:, properties:, time:)
         │
         ▼
Creates Ahoy::Event with user_id (visit_id = nil)
```

**Note:** Server-side events (from jobs/callbacks) have `visit_id: nil` since there's no HTTP request context. They still have `user_id` for user association.

---

## Configuration

**config/initializers/ahoy.rb**
```ruby
class Ahoy::Store < Ahoy::DatabaseStore
end

# Enable JavaScript tracking endpoint
Ahoy.api = true

# Privacy-first: Cookieless mode
Ahoy.cookies = :none

# Don't track bots
Ahoy.track_bots = false

# Mask IP addresses for privacy
Ahoy.mask_ips = true

# Disable geocoding (no external lookups)
Ahoy.geocode = false
```

---

## Testing/Verification

### Rails Console Checks

```ruby
# Verify tables exist
Ahoy::Visit.count
Ahoy::Event.count

# Verify events are tracked
Ahoy::Event.group(:name).count

# Check user association
Ahoy::Event.where.not(user_id: nil).group(:name).count

# Events for a specific user
user = User.last
Ahoy::Event.where(user_id: user.id).pluck(:name, :time)

# Guest events
Ahoy::Event.where(user_id: nil).group(:name).count
```

### Manual Testing Checklist

1. [ ] Visit home page as guest - creates `ahoy_visit` with `user_id = NULL`
2. [ ] Perform lookup as guest - tracks `guest_lookup_performed`
3. [ ] Hit 3-lookup limit - tracks `guest_limit_reached`
4. [ ] Sign up new account - tracks `user_account_created` with `user_id`
5. [ ] Perform lookup as user - tracks `user_lookup_performed` with `user_id`
6. [ ] Forward an email - tracks `user_email_forwarded` with `user_id`
7. [ ] Confirm a commodity code - tracks `commodity_code_confirmed` with `user_id`

---

## BI Integration (Metabase/Looker)

Connect your BI tool directly to the PostgreSQL database. Key tables:
- `ahoy_visits` - Session/visitor data
- `ahoy_events` - All tracked events with `properties` JSON

### Sample Queries

**Page views per page:**
```sql
SELECT
  properties->>'page' as page,
  COUNT(*) as views
FROM ahoy_events
WHERE name = 'page_view'
  AND time > NOW() - INTERVAL '7 days'
GROUP BY properties->>'page'
ORDER BY views DESC;
```

**Events per day:**
```sql
SELECT DATE(time) as date, name, COUNT(*) as count
FROM ahoy_events
GROUP BY DATE(time), name
ORDER BY date DESC;
```

**User activity funnel:**
```sql
SELECT
  COUNT(DISTINCT CASE WHEN name = 'user_account_created' THEN user_id END) as signups,
  COUNT(DISTINCT CASE WHEN name = 'user_lookup_performed' THEN user_id END) as lookups,
  COUNT(DISTINCT CASE WHEN name = 'commodity_code_confirmed' THEN user_id END) as confirms
FROM ahoy_events
WHERE time > NOW() - INTERVAL '30 days';
```

**Top commodity codes confirmed:**
```sql
SELECT
  properties->>'commodity_code' as code,
  COUNT(*) as confirms
FROM ahoy_events
WHERE name = 'commodity_code_confirmed'
GROUP BY properties->>'commodity_code'
ORDER BY confirms DESC
LIMIT 20;
```

**Commodity Code Confirmation Rate:**
```sql
SELECT
  DATE(time) as date,
  SUM(CASE WHEN name = 'commodity_code_suggested' THEN 1 ELSE 0 END) as suggested,
  SUM(CASE WHEN name = 'commodity_code_confirmed' THEN 1 ELSE 0 END) as confirmed
FROM ahoy_events
WHERE name IN ('commodity_code_suggested', 'commodity_code_confirmed')
  AND time > NOW() - INTERVAL '30 days'
GROUP BY DATE(time)
ORDER BY date;
```

---

## Admin Analytics Dashboard

### Route
`GET /admin/analytics` - Requires admin authentication

### Features
- **Date range selection**: 7 days, 30 days, 90 days, 1 year
- **Visitor stats**: Total visitors, total visits, visitors by day chart
- **Lookup stats**: Total lookups, lookups by source (homepage guest/user, extension, photo upload, email forwarding)
- **Signup stats**: Total signups, signups by day chart, conversion rate
- **Usage trends**: Active users, repeat users, average lookups per user
- **Top referrers**: Traffic source breakdown
- **Device breakdown**: Desktop/mobile/tablet split

### Charts
Uses `simple_chart_controller.js` - a CSP-compliant Canvas-based line chart that doesn't require external libraries or inline JavaScript.

---

## Seeding Mock Data

For development/testing, use the rake tasks:

```bash
# Seed 90 days of realistic mock data
bin/rails analytics:seed

# Clear all seeded data
bin/rails analytics:clear
```

The seeder creates:
- Visits with realistic patterns (weekday peaks, weekend dips)
- Guest and user lookup events
- Sign-up events with conversion rate simulation
- Extension lookup events

---

## Limitations & Future Improvements

### Current Limitations
- No JavaScript tracking: Only server-side events are tracked. Client-side interactions (scroll depth, time on page) are not tracked.
- No real-time dashboard updates (page refresh required)

### Future Improvements
- Add data retention job to purge events older than N days
- Implement cohort analysis queries
- Add `ahoy.js` for client-side event tracking
- Add A/B testing support via properties
- Export to CSV functionality

---

## Files Summary

### New Files (12)
- `config/initializers/ahoy.rb`
- `app/models/ahoy/visit.rb`
- `app/models/ahoy/event.rb`
- `app/controllers/concerns/trackable.rb`
- `app/services/analytics_tracker.rb`
- `db/migrate/20260117171118_create_ahoy_visits_and_events.rb`
- `app/controllers/admin/analytics_controller.rb`
- `app/views/admin/analytics/index.html.erb`
- `app/controllers/users/registrations_controller.rb`
- `app/javascript/controllers/simple_chart_controller.js`
- `lib/tasks/seed_analytics.rake`
- `db/migrate/20260123205132_change_ahoy_events_properties_to_jsonb.rb`

### Modified Files (12)
- `Gemfile`
- `app/controllers/application_controller.rb`
- `app/controllers/pages_controller.rb`
- `app/controllers/product_lookups_controller.rb`
- `app/controllers/orders_controller.rb`
- `app/models/user.rb`
- `app/jobs/process_inbound_email_job.rb`
- `app/jobs/suggest_commodity_codes_job.rb`
- `app/controllers/api/v1/extension_controller.rb`
- `config/routes.rb`
- `config/database.yml`
- `docker-compose.yml`
