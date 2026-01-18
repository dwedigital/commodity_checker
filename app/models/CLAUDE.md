# Models - AI Context

ActiveRecord models for the application.

## Model Relationships

```
User (Devise)
├── has_many :orders
├── has_many :inbound_emails
├── has_many :api_keys
└── has_many :webhooks

ApiKey
├── belongs_to :user
└── has_many :api_requests

ApiRequest
└── belongs_to :api_key

BatchJob
├── belongs_to :api_key
└── has_many :batch_job_items

BatchJobItem
└── belongs_to :batch_job

Webhook
└── belongs_to :user

Order
├── belongs_to :user
├── belongs_to :source_email (InboundEmail, optional) - email that created the order
├── has_many :order_items
├── has_many :tracking_events
└── has_many :inbound_emails - all emails related to this order

OrderItem
└── belongs_to :order

TrackingEvent
└── belongs_to :order

InboundEmail
├── belongs_to :user
├── belongs_to :order (optional) - linked by order reference
└── has_one :created_order (legacy alias for source_email)
```

## User

Devise authentication with additional fields:
- `inbound_email_token` - Unique hex token for email forwarding
- `subscription_tier` - enum: free, starter, professional, enterprise
- `subscription_expires_at` - Datetime for subscription expiry
- Generated on create via `before_create :generate_inbound_email_token`

**Subscription tier enum:**
```ruby
enum :subscription_tier, { free: 0, starter: 1, professional: 2, enterprise: 3 }
```

**Key methods:**
```ruby
user.inbound_email_address
# => "track-abc123@inbound.tariffik.com"

user.has_api_access?
# => true if subscription_tier is starter, professional, or enterprise AND not expired

user.subscription_active?
# => true if subscription_expires_at is nil or in the future
```

## Order

Represents a purchase from a retailer.

**Attributes:**
- `order_reference` - External order number (from email)
- `retailer_name` - Identified retailer
- `status` - enum: pending, in_transit, delivered
- `estimated_delivery` - Date if known
- `source_email_id` - The email that created this order

**Associations:**
- `source_email` - The InboundEmail that created this order
- `inbound_emails` - All InboundEmails linked to this order (by order reference)

**Status enum:**
```ruby
enum :status, { pending: 0, in_transit: 1, delivered: 2 }
```

**Get all related emails:**
```ruby
order.inbound_emails  # All emails with matching order reference
order.source_email    # The email that created the order
```

## OrderItem

Individual product within an order.

**Key attributes:**
- `description` - Product name/description
- `quantity` - Number of items
- `suggested_commodity_code` - AI-suggested HS code
- `confirmed_commodity_code` - User-confirmed code
- `commodity_code_confidence` - Float 0.0-1.0
- `llm_reasoning` - AI explanation
- `image_url` - Product thumbnail URL (from email or Tavily search)
- `product_url` - URL to product page on retailer site
- `scraped_description` - Enhanced description from web scraping

**Helper method:**
```ruby
item.commodity_code_confirmed?
# => true if confirmed_commodity_code.present?
```

**Image sources (in priority order):**
1. Extracted from email HTML
2. Found via Tavily web search
3. Scraped from product page

## TrackingEvent

Snapshot of delivery tracking status.

**Attributes:**
- `carrier` - Carrier name (royal_mail, dhl, etc.)
- `tracking_url` - Full URL to tracking page
- `status` - Current status text
- `location` - Last known location
- `event_timestamp` - When status was recorded
- `raw_data` - JSON of full scraper response

## InboundEmail

Stored forwarded email.

**Attributes:**
- `subject` - Email subject line
- `from_address` - Sender email
- `body_text` - Plain text body (HTML stripped)
- `body_html` - Raw HTML body (for image extraction)
- `processing_status` - enum: received, processing, completed, failed
- `processed_at` - Timestamp
- `order_id` - Links email to order by order reference

**Associations:**
- `order` - The order this email is linked to (by order reference)
- `created_order` - Legacy: order that was created from this email

**Status enum:**
```ruby
enum :processing_status, { received: 0, processing: 1, completed: 2, failed: 3 }
```

**Get related order:**
```ruby
email.order           # Order linked by order reference
email.created_order   # Order where this is the source_email (legacy)
```

## ApiKey

API authentication token with tiered rate limiting.

**Attributes:**
- `key_prefix` - First 15 chars of key (for lookup)
- `key_digest` - SHA256 hash (for verification)
- `name` - User-friendly name
- `tier` - enum: trial, starter, professional, enterprise
- `requests_today` / `requests_this_month` - Usage counters
- `last_request_at` - Timestamp
- `revoked_at` - Soft delete timestamp

**Tier enum:**
```ruby
enum :tier, { trial: 0, starter: 1, professional: 2, enterprise: 3 }
```

**Key methods:**
```ruby
api_key.raw_key        # Only available immediately after create
api_key.revoke!        # Soft delete the key
api_key.revoked?       # Check if revoked
api_key.increment_usage! # Track a request

# Class method for authentication
ApiKey.authenticate("tk_live_abc123...")  # Returns ApiKey or nil
```

**Rate limits by tier:**
```ruby
api_key.requests_per_minute_limit  # 5/30/100/500
api_key.requests_per_day_limit     # 50/1000/10000/unlimited
api_key.batch_size_limit           # 5/25/100/500
```

**Validation:**
- API key tier cannot exceed user's subscription tier
- User must have API access (starter+ subscription)

## ApiRequest

Request logging for analytics.

**Attributes:**
- `api_key_id` - Foreign key
- `endpoint` - Request path
- `status_code` - HTTP response code
- `response_time_ms` - Performance tracking
- `created_at` - Timestamp

## BatchJob

Tracks async batch processing status.

**Attributes:**
- `api_key_id` - Foreign key
- `status` - enum: pending, processing, completed, failed
- `total_items` / `completed_items` / `failed_items` - Counters
- `webhook_url` - Optional URL for completion notification
- `results` - JSON with full results

**Status enum:**
```ruby
enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
```

**Key methods:**
```ruby
batch_job.finished?        # completed or failed
batch_job.mark_completed!  # Set status, trigger webhook
batch_job.as_json_response # Full response with results
```

## BatchJobItem

Individual item within a batch.

**Attributes:**
- `batch_job_id` - Foreign key
- `external_id` - Client-provided ID
- `input_type` - enum: description, url
- `description` / `url` - Input data
- `status` - enum: pending, processing, completed, failed
- `commodity_code` / `confidence` / `reasoning` - Results
- `scraped_product` - JSON (for URL items)
- `error_message` - Failure reason

## Webhook

User webhook configuration.

**Attributes:**
- `user_id` - Foreign key
- `url` - HTTPS URL for delivery
- `secret` - HMAC signing secret
- `events` - JSON array of subscribed events
- `enabled` - Toggle
- `failure_count` - For circuit breaking
- `last_success_at` / `last_failure_at` - Timestamps

**Key methods:**
```ruby
webhook.subscribes_to?("batch.completed")  # Check subscription
webhook.record_success! / webhook.record_failure!
```

## Database Indexes

Key indexes for performance:
- `users.inbound_email_token` - Unique, for email routing
- `orders.user_id` - For user's orders
- `order_items.order_id` - For order's items
- `tracking_events.order_id` - For order's tracking
- `api_keys.key_prefix` - For authentication lookup
- `api_keys.user_id` - For user's keys
- `api_requests.api_key_id` - For key's requests
- `batch_jobs.api_key_id` - For key's batch jobs
- `webhooks.user_id` - For user's webhooks

## Migrations

Located in `db/migrate/`. Run with:
```bash
bin/rails db:migrate
```

Schema is in `db/schema.rb`.
