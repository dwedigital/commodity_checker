# API Layer Premium Feature Implementation

## Overview

This implementation adds a premium API layer to Tariffik, enabling programmatic commodity code lookups with:
- API key authentication tied to user accounts
- Tiered rate limiting (trial, starter, professional, enterprise)
- Sync endpoints for fast lookups (~300ms-4s depending on operation)
- Async/webhook endpoints for batch processing
- Usage tracking and analytics

## Design Decisions

### Authentication Strategy
- **Bearer token authentication** via `Authorization: Bearer tk_live_...` header
- Keys are prefixed with `tk_live_` (production) or `tk_test_` (development) for visibility
- Keys stored as SHA256 digest with first 15 chars stored as prefix for efficient lookup
- This allows quick lookup by prefix + secure verification via digest comparison

### Rate Limiting Approach
- **Rack::Attack middleware** for per-minute throttling (before app processes request)
- **Application-level daily limits** tracked on ApiKey model
- Custom middleware extracts API key tier before Rack::Attack runs
- Tiered limits: Trial (5/min, 50/day) → Enterprise (500/min, unlimited)

### Batch Processing
- Async via Solid Queue background jobs
- Items processed individually to allow partial completion
- Webhook delivery on completion with HMAC-SHA256 signature verification
- Polling endpoint available as alternative to webhooks

## Database Changes

### New Tables

| Table | Purpose |
|-------|---------|
| `api_keys` | API authentication tokens with tier and usage tracking |
| `api_requests` | Request logging for analytics |
| `batch_jobs` | Track async batch processing status |
| `batch_job_items` | Individual items within batches |
| `webhooks` | User webhook configurations |

### User Model Updates
- Added `subscription_tier` enum (free, starter, professional, enterprise)
- Added `subscription_expires_at` datetime
- Added `has_many :api_keys` and `has_many :webhooks`

### Migrations Created

```
20260118110517_add_subscription_to_users.rb
20260118110526_create_api_keys.rb
20260118110527_create_api_requests.rb
20260118110528_create_batch_jobs.rb
20260118110529_create_batch_job_items.rb
20260118110530_create_webhooks.rb
```

## New Files Created

### Models

| File | Purpose |
|------|---------|
| `app/models/api_key.rb` | API key with tier, usage tracking, authentication |
| `app/models/api_request.rb` | Request logging for analytics |
| `app/models/batch_job.rb` | Batch job tracking with status, results |
| `app/models/batch_job_item.rb` | Individual batch items |
| `app/models/webhook.rb` | Webhook URL configuration |

### Controllers

| File | Purpose |
|------|---------|
| `app/controllers/api/v1/base_controller.rb` | Auth, error handling, rate limit headers |
| `app/controllers/api/v1/commodity_codes_controller.rb` | Search, suggest, batch endpoints |
| `app/controllers/api/v1/batch_jobs_controller.rb` | Batch status polling |
| `app/controllers/api/v1/webhooks_controller.rb` | Webhook CRUD |
| `app/controllers/api/v1/usage_controller.rb` | Usage statistics |
| `app/controllers/developer_controller.rb` | User dashboard for API key management |

### Views

| File | Purpose |
|------|---------|
| `app/views/developer/index.html.erb` | API dashboard with usage stats, keys, requests |
| `app/views/developer/upsell.html.erb` | Upsell page for free users |

### Services

| File | Purpose |
|------|---------|
| `app/services/api_commodity_service.rb` | Wraps scraper + suggester for API use |
| `app/services/webhook_signer.rb` | HMAC-SHA256 payload signing |

### Jobs

| File | Purpose |
|------|---------|
| `app/jobs/api_batch_processing_job.rb` | Orchestrates batch processing |
| `app/jobs/api_batch_item_job.rb` | Processes individual batch items |
| `app/jobs/webhook_delivery_job.rb` | Delivers webhooks with retries |

### Configuration

| File | Purpose |
|------|---------|
| `config/initializers/rack_attack.rb` | Rate limiting configuration |

### Tests

| File | Tests |
|------|-------|
| `test/models/api_key_test.rb` | 14 tests |
| `test/models/batch_job_test.rb` | 10 tests |
| `test/services/webhook_signer_test.rb` | 14 tests |
| `test/controllers/api/v1/commodity_codes_controller_test.rb` | 17 tests |
| `test/controllers/api/v1/batch_jobs_controller_test.rb` | 7 tests |
| `test/controllers/api/v1/usage_controller_test.rb` | 10 tests |
| `test/controllers/api/v1/webhooks_controller_test.rb` | 11 tests |

### Fixtures

| File | Purpose |
|------|---------|
| `test/fixtures/api_keys.yml` | API key test data |
| `test/fixtures/api_requests.yml` | Request log test data |
| `test/fixtures/batch_jobs.yml` | Batch job test data |
| `test/fixtures/batch_job_items.yml` | Batch item test data |
| `test/fixtures/webhooks.yml` | Webhook test data |

### Test Support

| File | Purpose |
|------|---------|
| `test/support/api_test_helper.rb` | API test helpers, stub methods |

## Modified Files

| File | Changes |
|------|---------|
| `Gemfile` | Added rack-attack, pagy gems |
| `config/routes.rb` | Added /api/v1 namespace and /developer routes |
| `app/models/user.rb` | Added subscription_tier, api_keys, webhooks associations, has_api_access? |
| `app/views/layouts/application.html.erb` | Added API link to navigation |

## Routes

```
# API Endpoints
GET    /api/v1/commodity-codes/search          # Search tariff API
GET    /api/v1/commodity-codes/:id             # Get code details
POST   /api/v1/commodity-codes/suggest         # AI suggestion (sync)
POST   /api/v1/commodity-codes/suggest-from-url # AI suggestion from URL (async)
POST   /api/v1/commodity-codes/batch           # Batch processing (async)
GET    /api/v1/batch-jobs                      # List batch jobs
GET    /api/v1/batch-jobs/:id                  # Get batch status/results
GET    /api/v1/webhooks                        # List webhooks
POST   /api/v1/webhooks                        # Create webhook
GET    /api/v1/webhooks/:id                    # Get webhook details
PATCH  /api/v1/webhooks/:id                    # Update webhook
DELETE /api/v1/webhooks/:id                    # Delete webhook
POST   /api/v1/webhooks/:id/test               # Send test webhook
GET    /api/v1/usage                           # Current usage stats
GET    /api/v1/usage/history                   # Usage history

# User Dashboard
GET    /developer                              # API dashboard (or upsell for free users)
POST   /developer/api-keys                     # Create API key
DELETE /developer/api-keys/:id                 # Revoke API key
```

## Data Flow

### Sync Suggestion Request
```
API Request
     │
     ▼
┌─────────────────────────────────────────┐
│ Rack::Attack (rate limiting)            │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ ApiKeyRateLimitMiddleware               │
│ - Extract API key from Bearer token     │
│ - Set rate limit for tier               │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ Api::V1::BaseController                 │
│ - authenticate_api_key!                 │
│ - check_rate_limit! (daily)             │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ CommodityCodesController#suggest        │
│ - Validate description                  │
│ - Call ApiCommodityService              │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ ApiCommodityService                     │
│ - Call LlmCommoditySuggester            │
│ - Returns commodity code + confidence   │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ Response (JSON)                         │
│ - commodity_code, confidence, etc.      │
│ - usage stats in response               │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ after_action: log_request               │
│ after_action: increment_usage           │
└─────────────────────────────────────────┘
```

### Batch Processing Flow
```
POST /api/v1/commodity-codes/batch
     │
     ▼
┌─────────────────────────────────────────┐
│ CommodityCodesController#batch          │
│ - Validate items array                  │
│ - Check batch size limit                │
│ - Create BatchJob + BatchJobItems       │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ ApiBatchProcessingJob (Solid Queue)     │
│ - Update status to processing           │
│ - Enqueue ApiBatchItemJob for each item │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ ApiBatchItemJob (per item)              │
│ - Process description or URL            │
│ - Update BatchJobItem with result       │
│ - Increment completed/failed count      │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ On batch completion:                    │
│ - Mark BatchJob as completed            │
│ - If webhook_url: WebhookDeliveryJob    │
└─────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│ WebhookDeliveryJob                      │
│ - Sign payload with HMAC-SHA256         │
│ - POST to webhook_url                   │
│ - Retry with exponential backoff        │
└─────────────────────────────────────────┘
```

## Testing/Verification

### Run Tests
```bash
# All tests (including 83 new API tests)
bin/rails test

# API controller tests only
bin/rails test test/controllers/api/v1/

# API model tests only
bin/rails test test/models/api_key_test.rb test/models/batch_job_test.rb

# Service tests
bin/rails test test/services/webhook_signer_test.rb
```

### Manual Testing

1. **Create an API key** (via Rails console):
```ruby
user = User.first
api_key = user.api_keys.create!(name: "Test Key", tier: :starter)
puts api_key.raw_key  # Save this - only shown once!
```

2. **Test search endpoint**:
```bash
curl -X GET "http://localhost:3000/api/v1/commodity-codes/search?q=cotton%20t-shirt" \
  -H "Authorization: Bearer tk_test_YOUR_KEY_HERE" \
  -H "Content-Type: application/json"
```

3. **Test sync suggestion**:
```bash
curl -X POST http://localhost:3000/api/v1/commodity-codes/suggest \
  -H "Authorization: Bearer tk_test_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{"description": "Cotton t-shirt, blue, size M"}'
```

4. **Test batch processing**:
```bash
curl -X POST http://localhost:3000/api/v1/commodity-codes/batch \
  -H "Authorization: Bearer tk_test_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {"id": "sku-001", "description": "Cotton shirt"},
      {"id": "sku-002", "description": "Leather wallet"}
    ]
  }'
```

5. **Poll for results**:
```bash
curl http://localhost:3000/api/v1/batch-jobs/BATCH_ID_HERE \
  -H "Authorization: Bearer tk_test_YOUR_KEY_HERE"
```

6. **Check usage**:
```bash
curl http://localhost:3000/api/v1/usage \
  -H "Authorization: Bearer tk_test_YOUR_KEY_HERE"
```

## Rate Limiting Tiers

| Tier | Requests/min | Requests/day | Batch Size |
|------|-------------|--------------|------------|
| Trial | 5 | 50 | 5 |
| Starter | 30 | 1,000 | 25 |
| Professional | 100 | 10,000 | 100 |
| Enterprise | 500 | Unlimited | 500 |

## Subscription & Access Control

### Tier Restrictions
- **Free users**: No API access (see upsell page at `/developer`)
- **Starter+**: Full API access with tier-appropriate rate limits
- API key tier cannot exceed user's subscription tier

### User Dashboard
- Route: `/developer`
- Free users see upsell page
- Subscribers see:
  - Usage stats (today, this month, rate limits)
  - API keys management (create, revoke)
  - Recent API requests table
  - Quick start code example

## Limitations & Future Improvements

### Current Limitations
1. **No subscription payment integration** - Tier changes are manual
2. **Webhook delivery retries** - Limited to 3 attempts with exponential backoff
3. **No API documentation page** - Only this implementation doc

### Future Improvements
1. **Stripe integration** for subscription payments
2. **API documentation page** with interactive examples
3. **More webhook events** - Currently only batch.completed
4. **Rate limit headers** - Add X-RateLimit-* headers to responses
5. **API versioning** - Plan for v2 with breaking changes
6. **Caching** - Cache tariff API results for common queries
7. **Batch prioritization** - Premium tiers get faster processing

## Security Considerations

- API keys are hashed with SHA256 for storage
- Keys prefixed `tk_live_`/`tk_test_` for environment visibility
- Webhook payloads signed with HMAC-SHA256
- Rate limiting at Rack middleware level (before app)
- Request logging excludes sensitive data
- HTTPS enforced in production
