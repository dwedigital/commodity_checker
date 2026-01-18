# Free User Lookup Limits Implementation

## Overview

Implemented a 5 lookups/month limit for free account users and updated the homepage pricing section to show premium subscription tiers. Free users who exceed their monthly limit are blocked from performing additional lookups until the next month.

## Design Decisions

### Dynamic Counting Over Counter Columns
- Count `ProductLookup` records dynamically using `where(created_at: Time.current.beginning_of_month..)`
- No migration needed - existing `(user_id, created_at)` index is efficient
- No risk of counter drift from race conditions
- Simpler implementation without cache invalidation concerns

### Limit Enforcement Strategy
- Before action `check_lookup_limit` runs on `create` and `create_from_photo` actions
- Returns early for guest users (handled by quick_lookup which has its own weekly limit)
- Returns early for premium users (starter, professional, enterprise)
- Blocks free users at or above the limit with redirect + flash message

### Homepage Pricing Updates
- Renamed "Free Lookups" to "Guest Lookups" (3/week, no account)
- Changed "Free Account" from "Unlimited" to "5 lookups/month"
- Added "Need more lookups?" section with premium tiers (Starter £29, Professional £99, Enterprise custom)
- Premium tiers show "Coming soon" until Stripe integration

## Database Changes

No database changes required. The implementation uses dynamic counting of existing `ProductLookup` records.

## New Files Created

| File | Purpose |
|------|---------|
| `app/views/product_lookups/_limit_reached.html.erb` | Turbo Stream partial for limit reached state |
| `test/controllers/product_lookups_controller_test.rb` | Controller tests for limit enforcement |
| `test/fixtures/product_lookups.yml` | Fixtures for product lookup tests |
| `test/fixtures/files/test_image.png` | Test image for photo lookup tests |

## Modified Files

| File | Changes |
|------|---------|
| `app/models/user.rb` | Added `FREE_MONTHLY_LOOKUP_LIMIT` constant, `can_perform_lookup?`, `lookups_this_month`, `lookups_remaining`, `premium?` methods |
| `app/controllers/product_lookups_controller.rb` | Added `check_lookup_limit` before action |
| `app/views/pages/home.html.erb` | Updated pricing section with Guest/Free Account/Premium tiers |
| `app/views/product_lookups/index.html.erb` | Added remaining lookups banner for free users |
| `app/views/product_lookups/new.html.erb` | Added limit indicator for free users |
| `test/models/user_test.rb` | Added tests for lookup limit methods |

## Routes

No new routes added. Uses existing product_lookups routes.

## Data Flow

```
User performs lookup
         │
         ▼
check_lookup_limit before_action
         │
    ┌────┴────┐
    │ Guest?  │──Yes──▶ Skip check (use quick_lookup weekly limit)
    └────┬────┘
         │No
    ┌────┴────┐
    │Premium? │──Yes──▶ Allow (no limit)
    └────┬────┘
         │No (Free user)
    ┌────┴─────────────┐
    │lookups_this_month│
    │  < 5 limit?      │
    └────┬───────┬─────┘
        Yes     No
         │       │
         ▼       ▼
    Continue   Redirect with
    to action  "limit reached" alert
```

## UI Components

### Index Page Banner (Free Users)
- Blue info banner showing "X of 5 free lookups remaining this month"
- Amber warning banner when limit reached with reset date
- Links to pricing section for upgrade

### New Lookup Page Indicator (Free Users)
- Blue info box showing remaining lookups
- Amber warning box when limit reached with upgrade CTA

### Limit Reached Partial (Turbo Stream)
- Gradient orange/amber card
- Shows limit reached message with reset date
- "Upgrade for unlimited" and "View history" buttons

### Guest Lookup Limit (No Account)
- 3 lookups total (forever, not per week)
- Cookie persists for 10 years to enforce the limit
- All-time counting via `GuestLookup.count_for_token(token)` (no window)
- Users can clear cookies to bypass, but this is acceptable for a free tier

### Homepage Pricing Section
1. **Free Tiers Row**:
   - Guest Lookups (3 total) - no account required
   - Free Account (5/month) - "Most Popular" badge
2. **Professional Tier**:
   - Unlimited lookups
   - API access from 20 requests/day
   - Batch processing from 10 items
   - Webhooks for automation
   - Coming soon: MCP server for agentic integration
   - "Contact us" button (no pricing displayed)

## Testing/Verification

### Run Tests
```bash
# Model tests
bin/rails test test/models/user_test.rb

# Controller tests
bin/rails test test/controllers/product_lookups_controller_test.rb

# All tests
bin/rails test
```

### Manual Testing

1. **As free user (5 lookups remaining)**:
   - Visit `/product_lookups` - see blue "5 of 5 free lookups remaining"
   - Visit `/product_lookups/new` - see limit indicator
   - Perform a lookup - count decreases

2. **As free user (limit reached)**:
   - Create 5 lookups this month
   - Visit `/product_lookups` - see amber "limit reached" banner
   - Try to create lookup - blocked with redirect and alert
   - Try photo lookup - also blocked

3. **As premium user**:
   - No limit banners shown
   - Can perform unlimited lookups

4. **Homepage pricing**:
   - Visit homepage, scroll to pricing section
   - Verify Guest/Free Account/Premium tier cards

## Limitations & Future Improvements

### Current Limitations
- Premium tier buttons show "Coming soon" (no Stripe integration yet)
- No email notification when approaching/hitting limit
- No in-app notification system for limit warnings

### Future Improvements
- Add Stripe integration for premium subscriptions
- Add email notifications at 4/5 lookups and when limit reached
- Add "rollover" unused lookups option for premium tiers
- Consider usage analytics dashboard for users
- Add option to purchase additional lookup packs
