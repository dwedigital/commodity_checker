# Models - AI Context

ActiveRecord models for the application.

## Model Relationships

```
User (Devise)
├── has_many :orders
└── has_many :inbound_emails

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
- Generated on create via `before_create :generate_inbound_email_token`

**Key method:**
```ruby
user.inbound_email_address
# => "track-abc123@inbound.tariffik.com"
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

## Database Indexes

Key indexes for performance:
- `users.inbound_email_token` - Unique, for email routing
- `orders.user_id` - For user's orders
- `order_items.order_id` - For order's items
- `tracking_events.order_id` - For order's tracking

## Migrations

Located in `db/migrate/`. Run with:
```bash
bin/rails db:migrate
```

Schema is in `db/schema.rb`.
