# Models - AI Context

ActiveRecord models for the application.

## Model Relationships

```
User (Devise)
├── has_many :orders
└── has_many :inbound_emails

Order
├── belongs_to :user
├── belongs_to :source_email (InboundEmail, optional)
├── has_many :order_items
└── has_many :tracking_events

OrderItem
└── belongs_to :order

TrackingEvent
└── belongs_to :order

InboundEmail
└── belongs_to :user
```

## User

Devise authentication with additional fields:
- `inbound_email_token` - Unique hex token for email forwarding
- Generated on create via `before_create :generate_inbound_email_token`

**Key method:**
```ruby
user.inbound_email_address
# => "track-abc123@inbound.example.com"
```

## Order

Represents a purchase from a retailer.

**Attributes:**
- `order_reference` - External order number (from email)
- `retailer_name` - Identified retailer
- `status` - enum: pending, in_transit, delivered
- `estimated_delivery` - Date if known

**Status enum:**
```ruby
enum :status, { pending: 0, in_transit: 1, delivered: 2 }
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

**Helper method:**
```ruby
item.commodity_code_confirmed?
# => true if confirmed_commodity_code.present?
```

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
- `processing_status` - enum: received, processing, completed, failed
- `processed_at` - Timestamp

**Status enum:**
```ruby
enum :processing_status, { received: 0, processing: 1, completed: 2, failed: 3 }
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
