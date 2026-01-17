# Ahoy Analytics Implementation

## Overview

Privacy-first analytics using the Ahoy gem. Cookieless mode, all data stored in your database, compatible with Metabase/Looker for dashboards.

**Why Ahoy:**
- No third-party cookies or tracking pixels
- All data stays in your PostgreSQL database
- Automatic user association for logged-in users
- Standard SQL tables for BI tools

---

## Design Decisions

### 1. Same Database
Ahoy tables (`ahoy_visits`, `ahoy_events`) go in the primary database alongside existing tables. The volume of analytics events won't stress the database at this scale.

### 2. Keep `GuestLookup` Model
The existing `GuestLookup` model is tightly coupled to rate-limiting logic (3 free lookups per week). Ahoy handles analytics separately - this separation of concerns is cleaner than trying to repurpose rate-limiting data for analytics.

### 3. Cookieless Mode
Visitor identification via hashed `IP + User-Agent + Date`. This rotates daily for privacy while still allowing session-like tracking within a day.

### 4. User ID Association
**Ahoy automatically associates events with users when logged in:**
- `ahoy_visits.user_id` - Links visits to users
- `ahoy_events.user_id` - Links every event to the user who triggered it
- When `current_user` exists, Ahoy captures `user_id` automatically
- Background jobs pass user explicitly: `AnalyticsTracker.new(user: order.user)`

---

## Database Changes

### New Tables

**ahoy_visits**
| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| visit_token | string | Unique visit identifier |
| visitor_token | string | Hashed visitor identifier (cookieless) |
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

**ahoy_events**
| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Primary key |
| visit_id | bigint | FK to ahoy_visits |
| user_id | bigint | **FK to users** (null for guests) |
| name | string | Event name (e.g., `order_created`) |
| properties | json | Event properties as JSON |
| time | datetime | When event occurred |

### Indexes
- `ahoy_visits.visit_token` (unique)
- `ahoy_visits.user_id`
- `ahoy_events.name, time`
- `ahoy_events.user_id`
- `ahoy_events.visit_id, name`

---

## New Files Created

| File | Purpose |
|------|---------|
| `config/initializers/ahoy.rb` | Ahoy configuration (cookieless mode, visitor token generator) |
| `app/controllers/concerns/trackable.rb` | Controller concern for tracking events |
| `app/services/analytics_tracker.rb` | Service for tracking events in background jobs |
| `db/migrate/*_create_ahoy_visits.rb` | Migration for visits table |
| `db/migrate/*_create_ahoy_events.rb` | Migration for events table |

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

---

## Events Schema

### Guest Events (user_id = NULL)

| Event | Properties | Trigger |
|-------|------------|---------|
| `guest_lookup_performed` | `guest_token`, `lookup_type`, `lookups_remaining`, `commodity_code` | PagesController#lookup |
| `guest_limit_reached` | `guest_token`, `lookup_count` | PagesController#lookup (when limit hit) |

### User Events (user_id = current_user.id)

| Event | Properties | Trigger |
|-------|------------|---------|
| `user_account_created` | `user_id` | User model after_create |
| `user_lookup_performed` | `lookup_id`, `lookup_type` | ProductLookupsController#create |
| `user_email_forwarded` | `email_id`, `email_type`, `retailer` | ProcessInboundEmailJob |
| `order_created` | `order_id`, `retailer`, `item_count`, `source` | OrdersController, ProcessInboundEmailJob |
| `commodity_code_suggested` | `order_item_id`, `commodity_code`, `confidence` | SuggestCommodityCodesJob |
| `commodity_code_confirmed` | `order_item_id`, `commodity_code`, `source` | OrdersController, ProductLookupsController |

---

## Data Flow

```
Guest Visit (no cookies)
    │
    ├─► Ahoy generates visitor_token from hash(IP + UA + Date)
    │
    ├─► Creates ahoy_visit record (user_id = NULL)
    │
    └─► Events tracked with visit_id, user_id = NULL

User Login
    │
    ├─► Ahoy updates visit with user_id = current_user.id
    │
    └─► All subsequent events include user_id automatically

Background Job (e.g., email processing)
    │
    ├─► AnalyticsTracker.new(user: order.user)
    │
    └─► Events tracked with explicit user_id
```

---

## Implementation Steps

### Step 1: Add Gems

```ruby
# Gemfile
gem 'ahoy_matey'
gem 'device_detector'
```

```bash
bundle install
```

### Step 2: Generate Ahoy

```bash
bin/rails generate ahoy:install
```

### Step 3: Configure Ahoy (Cookieless)

**config/initializers/ahoy.rb**
```ruby
class Ahoy::Store < Ahoy::DatabaseStore
end

Ahoy.api = true
Ahoy.cookies = false
Ahoy.track_bots = false
Ahoy.mask_ips = true
Ahoy.geocode = false

# Cookieless visitor identification
Ahoy.visitor_token_generator = ->(request) {
  data = "#{request.remote_ip}|#{request.user_agent}|#{Date.current}"
  Digest::SHA256.hexdigest(data)[0..31]
}
```

### Step 4: Create Trackable Concern

**app/controllers/concerns/trackable.rb**
```ruby
module Trackable
  extend ActiveSupport::Concern

  private

  def track_event(name, properties = {})
    ahoy.track(name, default_properties.merge(properties))
  end

  def default_properties
    { user_signed_in: user_signed_in? }
  end
end
```

### Step 5: Include in ApplicationController

```ruby
class ApplicationController < ActionController::Base
  include Trackable
  # ...
end
```

### Step 6: Create Analytics Service for Background Jobs

**app/services/analytics_tracker.rb**
```ruby
class AnalyticsTracker
  def initialize(user: nil)
    @tracker = Ahoy::Tracker.new(user: user)
  end

  def track(name, properties = {})
    @tracker.track(name, properties.merge(tracked_at: Time.current.iso8601))
  rescue => e
    Rails.logger.error("Analytics tracking failed: #{e.message}")
  end
end
```

### Step 7: Add Event Tracking

**PagesController** (guest lookups):
```ruby
def lookup
  # ... existing code ...

  if @guest_lookup_count >= GUEST_LOOKUP_LIMIT
    track_event('guest_limit_reached', {
      guest_token: @guest_token,
      lookup_count: @guest_lookup_count
    })
    # ...
  end

  # After successful lookup
  track_event('guest_lookup_performed', {
    guest_token: @guest_token,
    lookups_remaining: @guest_lookups_remaining,
    commodity_code: @suggestion&.dig(:commodity_code)
  })
end
```

**User model** (signups):
```ruby
class User < ApplicationRecord
  after_create :track_account_creation

  private

  def track_account_creation
    AnalyticsTracker.new(user: self).track('user_account_created', {
      user_id: id
    })
  end
end
```

**Background jobs**:
```ruby
# In ProcessInboundEmailJob
tracker = AnalyticsTracker.new(user: inbound_email.user)
tracker.track('user_email_forwarded', {
  email_id: inbound_email.id,
  email_type: classification
})
```

### Step 8: Run Migrations

```bash
bin/rails db:migrate
```

---

## Testing/Verification

### Rails Console Checks

```ruby
# Verify visits are recorded
Ahoy::Visit.count
Ahoy::Visit.where.not(user_id: nil).count  # Logged-in visits

# Verify events are tracked
Ahoy::Event.count
Ahoy::Event.group(:name).count

# Check user association
Ahoy::Event.where(name: 'order_created').where.not(user_id: nil).count

# Events for a specific user
user = User.last
Ahoy::Event.where(user_id: user.id).pluck(:name, :time)
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

**Guest to User Conversion:**
```sql
SELECT
  COUNT(DISTINCT CASE WHEN name = 'guest_limit_reached' THEN visitor_token END) as hit_limit,
  COUNT(DISTINCT CASE WHEN name = 'user_account_created' THEN visitor_token END) as signed_up
FROM ahoy_events
WHERE time > NOW() - INTERVAL '30 days';
```

**User Activity by User:**
```sql
SELECT
  u.email,
  COUNT(*) as total_events,
  COUNT(DISTINCT DATE(e.time)) as active_days
FROM ahoy_events e
JOIN users u ON e.user_id = u.id
WHERE e.time > NOW() - INTERVAL '30 days'
GROUP BY u.id, u.email
ORDER BY total_events DESC;
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

**Events per User (for understanding power users):**
```sql
SELECT
  user_id,
  name,
  COUNT(*) as count
FROM ahoy_events
WHERE user_id IS NOT NULL
GROUP BY user_id, name
ORDER BY user_id, count DESC;
```

---

## Limitations & Future Improvements

### Current Limitations
- No real-time dashboard (query database directly or use BI tool)
- Daily visitor token rotation means cross-day guest tracking is limited
- No automatic funnel visualization (build in BI tool)

### Future Improvements
- Add data retention job to purge events older than N days
- Consider async event tracking via Solid Queue for high traffic
- Add custom dashboard in Rails admin
- Implement cohort analysis queries
- Add A/B testing support via properties
