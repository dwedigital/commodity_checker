# Implementation: Delivery Date Extraction from Emails

## Overview

Added functionality to extract expected delivery dates from forwarded emails and populate the existing `estimated_delivery` field on orders. The system handles explicit dates, shipping method-based calculations, and day range extraction.

## Design Decisions

### Extraction Priority

The service tries extraction methods in order of confidence:

1. **Explicit dates** (0.9 confidence) - Direct date mentions like "ESTIMATED DELIVERY DATE: 2026-01-28"
2. **Relative dates** (0.9 confidence) - "tomorrow", "this Friday", "next Monday"
3. **Shipping method calculation** (0.7 confidence) - "Royal Mail 2nd Class" → calculate 2-3 business days
4. **Day range extraction** (0.6 confidence) - "3-5 business days" → use minimum (3)

### Business Day Calculation

Weekend days (Saturday/Sunday) are skipped when calculating delivery estimates from shipping methods or day ranges. For example, "2 business days" from Friday gives Tuesday (skipping Sat/Sun).

### Configuration-Driven Shipping Methods

Carrier and shipping method definitions are stored in YAML for easy maintenance and extension. This allows non-developers to update delivery windows without code changes.

### Past Date Validation

Extracted dates are validated against the email date. If the extracted delivery date is before the email was received, it's discarded as invalid.

## Database Changes

None. The `estimated_delivery` column already exists on the `orders` table.

## New Files Created

| File | Purpose |
|------|---------|
| `config/shipping_methods.yml` | Carrier/method definitions with delivery windows |
| `app/services/delivery_date_extractor_service.rb` | Core extraction logic with multiple strategies |
| `test/services/delivery_date_extractor_service_test.rb` | 38 unit tests covering all extraction methods |

## Modified Files

| File | Changes |
|------|---------|
| `app/services/email_parser_service.rb` | Added `extract_delivery_info` method to `parse` output |
| `app/jobs/process_inbound_email_job.rb` | Set `estimated_delivery` on order creation/update |

## Routes

No new routes added.

## Data Flow

```
Email Arrives
      │
      ▼
ProcessInboundEmailJob
      │
      ├─→ EmailParserService.parse()
      │         │
      │         └─→ extract_delivery_info()
      │               │
      │               └─→ DeliveryDateExtractorService.new(email_body:, email_date:).extract
      │                     │
      │                     ├─ try_explicit_date_extraction() → patterns for ISO, UK, US, natural dates
      │                     ├─ try_relative_date_extraction() → "tomorrow", "this Friday", "next Monday"
      │                     ├─ try_shipping_method_extraction() → config/shipping_methods.yml lookup
      │                     └─ try_day_range_extraction() → "3-5 business days" patterns
      │
      │   Returns: { delivery_info: { estimated_delivery:, confidence:, source:, ... } }
      │
      └─→ Create/Update Order
            │
            ├─ create_new_order() → order.estimated_delivery = delivery_info[:estimated_delivery]
            │
            └─ update_existing_order() / process_tracking_only()
                  │
                  └─ update_delivery_estimate(order, delivery_info)
                        │
                        └─ Updates if: order has no estimate OR new info is explicit date with high confidence
```

## Configuration Structure

`config/shipping_methods.yml`:

```yaml
carriers:
  royal_mail:
    patterns: ['royal mail', 'royalmail']
    methods:
      first_class:
        patterns: ['1st class', 'first class']
        min_days: 1
        max_days: 2
      second_class:
        patterns: ['2nd class', 'second class']
        min_days: 2
        max_days: 3
      # ... more methods

generic_methods:
  express:
    patterns: ['express', 'priority', 'expedited']
    min_days: 1
    max_days: 2
  # ... more generic methods

day_range_patterns:
  - '(\d+)\s*[-–]\s*(\d+)\s*(?:business\s+)?days?'
  - 'within\s+(\d+)\s*(?:business\s+)?days?'
  # ... more patterns
```

## Testing/Verification

### Run Unit Tests

```bash
bin/rails test test/services/delivery_date_extractor_service_test.rb
```

### Manual Testing

1. Navigate to `/dashboard/test_emails/new`
2. Paste an email with delivery date information:
   - Explicit: "ESTIMATED DELIVERY DATE: 2026-01-28"
   - Shipping method: "Shipping: Royal Mail 1st Class"
   - Day range: "Delivery in 3-5 business days"
3. Submit and verify the order shows the expected delivery date

### Verify in Rails Console

```ruby
# Test the service directly
extractor = DeliveryDateExtractorService.new(
  email_body: "Your order will arrive by January 28, 2026",
  email_date: Date.current
)
result = extractor.extract
# => { estimated_delivery: Date, confidence: 0.9, source: :explicit_date, ... }

# Test shipping method calculation
extractor = DeliveryDateExtractorService.new(
  email_body: "Shipped via Royal Mail 2nd Class",
  email_date: Date.new(2026, 1, 22) # Thursday
)
result = extractor.extract
# => { estimated_delivery: Mon 26 Jan 2026, confidence: 0.7, source: :shipping_method, shipping_method: "royal_mail/second_class" }
```

## Supported Date Formats

### Explicit Dates

- ISO: `2026-01-28`
- UK: `28/01/2026`, `28-01-2026`
- Natural: `January 28, 2026`, `Jan 28 2026`, `28 January 2026`
- Without year: `Arriving January 28` (assumes current/next year)
- Day of week: `Arriving Friday`

### Relative Dates

- `today`, `tomorrow`
- `this Friday`, `next Monday`

### Shipping Methods

Supported carriers: Royal Mail, DPD, Evri/Hermes, DHL, UPS, FedEx, Amazon, Yodel, USPS

Generic methods: express, next day, two day, standard

### Day Ranges

- `3-5 business days`
- `within 2 business days`
- `2 to 3 working days`
- `arrives in 5 days`
- `Delivery in 3 business days`

## Limitations & Future Improvements

### Current Limitations

1. **Holiday handling** - Business day calculation doesn't account for public holidays
2. **Regional date formats** - US dates (mm/dd/yyyy) not fully supported
3. **Shipping carrier coverage** - Only major UK/US carriers included
4. **Complex date expressions** - "end of next week", "mid-February" not supported

### Future Improvements

1. Add public holiday calendar support for accurate business day calculations
2. Add more international carriers (PostNL, La Poste, etc.)
3. Support time-specific delivery windows ("by 10pm tomorrow")
4. Machine learning for retailer-specific date patterns
5. Support for multiple date mentions (choose most specific)
