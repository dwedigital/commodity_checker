# Jobs - AI Context

Background jobs using Solid Queue (Rails 8 default).

## Job Overview

| Job | Trigger | Purpose |
|-----|---------|---------|
| `process_inbound_email_job.rb` | After email received | Parse email, create/update order |
| `suggest_commodity_codes_job.rb` | After order created/updated | Get AI code suggestions |
| `update_tracking_job.rb` | Manual refresh or scheduled | Scrape tracking status |
| `api_batch_processing_job.rb` | API batch endpoint | Orchestrate batch processing |
| `api_batch_item_job.rb` | Batch processing job | Process individual batch items |
| `webhook_delivery_job.rb` | Batch completion | Deliver webhooks with retries |
| `cleanup_orphaned_emails_job.rb` | Recurring (3am daily) | Delete old orphaned inbound emails |

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

## ApiBatchProcessingJob

**Triggered by:** `POST /api/v1/commodity-codes/batch`

**Flow:**
1. Load BatchJob, mark as `processing`
2. For each BatchJobItem:
   - Enqueue `ApiBatchItemJob`
3. Wait for all items to complete
4. Mark BatchJob as `completed`
5. If `webhook_url` set: enqueue `WebhookDeliveryJob`

**Key behaviors:**
- Items processed in parallel via separate jobs
- Progress tracked via `completed_items` / `failed_items` counters
- Partial success allowed (some items may fail)

## ApiBatchItemJob

**Triggered by:** `ApiBatchProcessingJob`

**Flow:**
1. Load BatchJobItem, mark as `processing`
2. Process based on `input_type`:
   - `description` → Call `ApiCommodityService.suggest_from_description`
   - `url` → Call `ApiCommodityService.suggest_from_url`
3. Update BatchJobItem with results
4. Mark as `completed` or `failed`
5. Increment parent BatchJob counters

**Error handling:**
- Catches exceptions, stores error_message
- Marks item as `failed`, doesn't stop batch
- Rate limiting: 0.5s delay between API calls

## WebhookDeliveryJob

**Triggered by:** `ApiBatchProcessingJob` or manual test

**Flow:**
1. Load Webhook and payload
2. Sign payload with `WebhookSigner`
3. POST to webhook URL with headers:
   - `Content-Type: application/json`
   - `X-Tariffik-Signature: sha256=...`
   - `X-Tariffik-Event: batch.completed`
4. On success: `webhook.record_success!`
5. On failure: `webhook.record_failure!`, retry

**Retry behavior:**
- 3 attempts with exponential backoff
- Delays: 30s, 5min, 30min
- Circuit breaker: disables webhook after 10 consecutive failures

**Supported events:**
- `batch.completed` - Batch processing finished
- `test` - Test webhook delivery

## CleanupOrphanedEmailsJob

**Triggered by:** Solid Queue recurring schedule (3am daily)

**Purpose:** Clean up orphaned `InboundEmail` records where the associated order was deleted.

When an order is destroyed, its `inbound_emails` have their `order_id` set to NULL (via `dependent: :nullify`). This job deletes those orphaned emails after a grace period (default 30 days) to:
- Prevent database bloat
- Allow recovery if order was deleted by mistake
- Maintain data hygiene

**Configuration:** `config/recurring.yml`
```yaml
cleanup_orphaned_emails:
  class: CleanupOrphanedEmailsJob
  args: [{ days_old: 30 }]
  schedule: at 3am every day
```

**Parameters:**
- `days_old` (default: 30) - Only delete orphaned emails older than this many days

## Recurring Jobs

Recurring jobs are configured in `config/recurring.yml` and run automatically by Solid Queue.

| Job | Schedule | Purpose |
|-----|----------|---------|
| `clear_solid_queue_finished_jobs` | Every hour | Prevent Solid Queue table bloat |
| `cleanup_orphaned_emails` | 3am daily | Delete orphaned inbound emails |

**Schedule syntax examples:**
- `every hour`
- `every 15 minutes`
- `at 3am every day`
- `every Monday at 9am`

**Adding a recurring job:**
1. Create the job class in `app/jobs/`
2. Add entry to `config/recurring.yml` under appropriate environment
3. Job runs automatically when Solid Queue starts

## Solid Queue Dashboard

Monitor jobs at `/admin/jobs` (requires admin user).

**Features:**
- View pending, running, and failed jobs
- Retry failed jobs
- View recurring job schedules
- Monitor queue health

**Access:** Requires `user.admin? == true`

## Adding New Jobs

1. Inherit from `ApplicationJob`
2. Set queue: `queue_as :default`
3. Implement `perform` method
4. Handle errors gracefully
5. Use `perform_later` for async, `perform_now` for sync
