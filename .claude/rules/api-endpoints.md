---
paths:
  - "app/controllers/api/**"
  - "app/models/api_key*"
  - "app/services/api_*"
  - "app/controllers/developer*"
  - "config/initializers/rack_attack*"
---

# Premium API

Tariffik offers a REST API for programmatic commodity code lookups at `/api/v1/`. Requires Starter subscription or higher.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         API Gateway Layer                           │
├─────────────────────────────────────────────────────────────────────┤
│  Rack::Attack (rate limiting) → API Authentication → Controllers   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              Sync Endpoint   Async Endpoint   Batch Endpoint
                    │              │              │
                    ▼              ▼              ▼
              Existing Services (TariffLookupService, LlmCommoditySuggester, ProductScraperService)
                              │
                              ▼ (for async/batch)
              Solid Queue Jobs (ApiBatchProcessingJob, ApiBatchItemJob, WebhookDeliveryJob)
```

## Authentication

All API requests require a Bearer token: `Authorization: Bearer tk_live_...`

## Key Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/commodity-codes/search?q=` | Search tariff codes |
| GET | `/api/v1/commodity-codes/:code` | Get code details |
| POST | `/api/v1/commodity-codes/suggest` | AI suggestion (sync) |
| POST | `/api/v1/commodity-codes/suggest-from-url` | AI from URL (async) |
| POST | `/api/v1/commodity-codes/batch` | Batch processing |
| GET | `/api/v1/batch-jobs/:id` | Poll batch status |
| GET | `/api/v1/usage` | Usage statistics |

## Rate Limits by Tier

| Tier | Requests/min | Requests/day | Batch Size |
|------|-------------|--------------|------------|
| Trial | 5 | 50 | 5 |
| Starter | 30 | 1,000 | 25 |
| Professional | 100 | 10,000 | 100 |
| Enterprise | 500 | Unlimited | 500 |

## Developer Dashboard

- Route: `/dashboard/developer`
- Free users see upsell page
- Subscribers see usage stats, API key management, recent requests

## API Key Management (Console)

```ruby
user = User.find_by(email: "user@example.com")
api_key = user.api_keys.create!(name: "My Key", tier: :starter)
puts api_key.raw_key  # Only shown once!
api_key.revoke!
```

See `claude/implementations/api-layer-premium-feature.md` for full implementation details.
