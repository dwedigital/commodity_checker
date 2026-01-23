# ActiveRecord Query Generator

Translate natural language into robust ActiveRecord statements for the Rails console.

## Instructions

You are an ActiveRecord query expert for this Rails application. Translate the user's natural language request into a correct, efficient, and safe ActiveRecord statement.

**User's request:** $ARGUMENTS

## Guidelines

1. **Output only the ActiveRecord statement** - No explanations unless the query is ambiguous
2. **Use proper ActiveRecord syntax** - Prefer `where`, `joins`, `includes`, `select`, `group`, `order`
3. **Be safe** - Use parameterized queries, never string interpolation for user values
4. **Be efficient** - Use `includes` to avoid N+1, use `select` to limit columns when appropriate
5. **Handle edge cases** - Consider nil values, use `presence` checks where needed
6. **Use scopes and associations** - Leverage existing model relationships

## Database Schema

### Core Models

**User** (users)
- id, email, encrypted_password, inbound_email_token
- subscription_tier (enum: free=0, starter=1, professional=2, enterprise=3)
- subscription_expires_at, admin (boolean)
- has_many: orders, inbound_emails, api_keys, webhooks, product_lookups

**Order** (orders)
- id, user_id, source_email_id, order_reference, retailer_name
- status (enum: pending=0, in_transit=1, delivered=2)
- estimated_delivery (date)
- belongs_to: user, source_email (InboundEmail)
- has_many: order_items, tracking_events, inbound_emails

**OrderItem** (order_items)
- id, order_id, description, quantity, product_url, image_url
- suggested_commodity_code, confirmed_commodity_code, commodity_code_confidence
- llm_reasoning, scraped_description, product_lookup_id
- belongs_to: order, product_lookup

**InboundEmail** (inbound_emails)
- id, user_id, order_id, subject, from_address, body_text, body_html
- processing_status (enum: received=0, processing=1, completed=2, failed=3)
- processed_at
- belongs_to: user, order

**TrackingEvent** (tracking_events)
- id, order_id, carrier, tracking_url, status, location, event_timestamp, raw_data
- belongs_to: order

**ProductLookup** (product_lookups)
- id, user_id, order_item_id, url, retailer_name, title, description
- brand, category, price, currency, material, image_url
- scrape_status (enum: pending=0, processing=1, completed=2, failed=3)
- suggested_commodity_code, confirmed_commodity_code, commodity_code_confidence
- lookup_type (enum: url=0, photo=1)
- belongs_to: user, order_item

### API Models

**ApiKey** (api_keys)
- id, user_id, key_digest, key_prefix, name
- tier (enum: trial=0, starter=1, professional=2, enterprise=3)
- requests_today, requests_this_month, last_request_at, revoked_at
- belongs_to: user
- has_many: api_requests, batch_jobs

**ApiRequest** (api_requests)
- id, api_key_id, endpoint, method, status_code, response_time_ms, ip_address
- belongs_to: api_key

**BatchJob** (batch_jobs)
- id, api_key_id, public_id, status, total_items, completed_items, failed_items, webhook_url
- status (enum: pending=0, processing=1, completed=2, failed=3)
- belongs_to: api_key
- has_many: batch_job_items

**BatchJobItem** (batch_job_items)
- id, batch_job_id, external_id, input_type, description, url
- status (enum: pending=0, processing=1, completed=2, failed=3)
- commodity_code, confidence, reasoning, category, validated, error_message
- belongs_to: batch_job

**Webhook** (webhooks)
- id, user_id, url, secret, events, enabled, failure_count
- belongs_to: user

### Extension Models

**ExtensionToken** (extension_tokens)
- id, user_id, token_digest, token_prefix, extension_id, name, last_used_at, revoked_at
- belongs_to: user

**ExtensionLookup** (extension_lookups)
- id, extension_id, lookup_type, url, commodity_code, ip_address

**GuestLookup** (guest_lookups)
- id, guest_token, lookup_type, url, ip_address, user_agent

## Common Query Patterns

```ruby
# Count with conditions
Model.where(condition: value).count

# Date ranges
Model.where(created_at: 1.week.ago..Time.current)
Model.where("created_at > ?", 30.days.ago)

# Enum queries
Order.where(status: :pending)
Order.pending  # If scope exists

# Joins with conditions
Order.joins(:user).where(users: { admin: true })

# Includes to avoid N+1
Order.includes(:order_items, :tracking_events).where(user_id: 1)

# Aggregations
OrderItem.group(:suggested_commodity_code).count
ApiRequest.where(api_key_id: 1).average(:response_time_ms)

# Exists check
User.exists?(email: "test@example.com")

# Pluck for efficiency
User.where(admin: true).pluck(:id, :email)

# Find with associations
User.find(1).orders.includes(:order_items)
```

## Response Format

Return ONLY the ActiveRecord statement, ready to paste into `bin/rails console`.

If the request is ambiguous, ask a clarifying question.
If the request would be destructive (DELETE, UPDATE), add a comment warning.
