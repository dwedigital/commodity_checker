# Jobs - AI Context

Background jobs using Solid Queue (Rails 8 default).

## Job Overview

| Job | Trigger | Purpose |
|-----|---------|---------|
| `process_inbound_email_job.rb` | After email received | Parse email, create/update order |
| `suggest_commodity_codes_job.rb` | After order created/updated | Get AI code suggestions |
| `update_tracking_job.rb` | Manual refresh or scheduled | Scrape tracking status |

## ProcessInboundEmailJob

**Triggered by:** `TrackingMailbox` after receiving forwarded email

**Flow:**
1. Find InboundEmail record
2. **AI Classification** - `EmailClassifierService` determines email type
3. **Regex Parsing** - `EmailParserService` extracts tracking URLs, images
4. **Merge data** - Combine AI classification with regex extraction
5. **Process by type:**
   - `order_confirmation` with products → Create order, extract images, suggest codes
   - `shipping_notification` → Match to existing order, add tracking
   - `delivery_confirmation` → Update tracking status
   - Others → Log and skip

**Key behaviors:**
- Marks email as `processing` → `completed` or `failed`
- **Links email to order** via `order_id` (by order reference)
- Extracts product images from email HTML
- Falls back to Tavily web search if no product URLs in email
- Avoids duplicate items/tracking when merging

**Image handling:**
1. Extract images from email HTML (preferred)
2. Filter out logos, icons, tracking pixels
3. Assign to order items by position
4. Fall back to Tavily search for images if none in email

**Email-to-order linking:**
- All emails with matching order reference are linked via `order_id`
- `Order.inbound_emails` returns all related emails
- `source_email` still tracks which email created the order

## SuggestCommodityCodesJob

**Triggered by:** ProcessInboundEmailJob or manual

**Flow:**
1. Load order with items
2. For each item without suggested code:
   - Call LlmCommoditySuggester
   - Save suggestion with confidence and reasoning
3. Rate limit: 0.5s between API calls

**Error handling:**
- Individual item failures don't stop processing
- Errors logged but job continues

## UpdateTrackingJob

**Triggered by:** Manual refresh button or can be scheduled

**Flow:**
1. Load order's tracking events with URLs
2. For each tracking URL:
   - Call TrackingScraperService
   - Update event with status, location, timestamp
3. Update order status based on latest tracking

**Status mapping:**
- `delivered` → Order delivered
- `out_for_delivery`, `in_transit` → Order in_transit
- Others → No change

## Running Jobs

```ruby
# Immediate (blocking)
SuggestCommodityCodesJob.perform_now(order_id)

# Async (via Solid Queue)
SuggestCommodityCodesJob.perform_later(order_id)
```

## Solid Queue Commands

```bash
# Start worker
bin/rails solid_queue:start

# In development, jobs run inline by default
# Check config/environments/development.rb
```

## Adding New Jobs

1. Inherit from `ApplicationJob`
2. Set queue: `queue_as :default`
3. Implement `perform` method
4. Handle errors gracefully
5. Use `perform_later` for async, `perform_now` for sync
