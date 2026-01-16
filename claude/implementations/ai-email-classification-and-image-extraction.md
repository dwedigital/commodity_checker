# AI Email Classification and Image Extraction

## Overview

This feature adds intelligent email processing using AI classification, automatic product image extraction from emails, and web search fallback for finding product details when emails lack product URLs.

**Key capabilities:**
- AI classifies email types (order confirmation, shipping notification, etc.)
- Extracts product images directly from email HTML
- Uses Tavily web search + AI to find product details when no URLs in email
- Links multiple emails to the same order by order reference number
- Detects tracking URLs including redirect links (Global-e, etc.)

## Design Decisions

### Why AI Classification?
- Different email types require different processing (order vs shipping vs delivery)
- AI can extract structured product data (name, brand, color, material) better than regex
- Reduces false positives from shipping-only emails creating unnecessary orders

### Why Extract Images from Email HTML?
- Order confirmation emails typically include product thumbnails
- More reliable than web search (guaranteed to match the ordered product)
- Faster than making external API calls

### Why Tavily for Web Search?
- Provides raw page content, not just snippets
- Includes images in search results
- AI-optimized search for extracting structured data

### Why Link Emails by Order Reference?
- Users forward multiple emails for same order (confirmation, shipping, delivery)
- Need to see all related emails in one place
- Better than relying solely on `source_email` which only tracks the creating email

## Database Changes

### New Columns

| Table | Column | Type | Purpose |
|-------|--------|------|---------|
| `order_items` | `image_url` | string | Product thumbnail URL |
| `inbound_emails` | `body_html` | text | Raw HTML for image extraction |
| `inbound_emails` | `order_id` | reference | Links email to order by reference |

### Migrations

```
db/migrate/20260116231400_add_image_url_to_order_items.rb
db/migrate/20260116231851_add_body_html_to_inbound_emails.rb
db/migrate/20260116233624_add_order_id_to_inbound_emails.rb
```

## New Files Created

| File | Purpose |
|------|---------|
| `app/services/email_classifier_service.rb` | AI classification of email types using Claude Haiku |
| `app/services/product_info_finder_service.rb` | Tavily web search + AI extraction for product details |
| `app/services/product_url_finder_service.rb` | Searches retailer sites for product pages |

## Modified Files

| File | Changes |
|------|---------|
| `app/services/email_parser_service.rb` | Added image extraction, Global-e tracking, redirect URL detection |
| `app/jobs/process_inbound_email_job.rb` | AI classification flow, image handling, email-order linking |
| `app/mailboxes/tracking_mailbox.rb` | Save HTML body for image extraction |
| `app/models/inbound_email.rb` | Added `belongs_to :order`, `created_order` alias |
| `app/models/order.rb` | Added `has_many :inbound_emails` |
| `app/views/orders/show.html.erb` | Display product thumbnails |

## Data Flow

### Email Processing Flow

```
Inbound Email
     │
     ▼
┌─────────────────┐
│ TrackingMailbox │ ─── Saves body_html + body_text
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ ProcessInboundEmailJob  │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ EmailClassifierService  │ ─── Claude Haiku classifies email type
└────────┬────────────────┘     Returns: email_type, products, retailer
         │
         ▼
┌─────────────────────────┐
│ EmailParserService      │ ─── Regex extraction
└────────┬────────────────┘     Returns: tracking_urls, product_images
         │
         ▼
┌─────────────────────────┐
│ Merge AI + Regex Data   │
└────────┬────────────────┘
         │
    ┌────┴────┐
    ▼         ▼
Order      Shipping
Confirmation  Notification
    │         │
    ▼         ▼
Create/   Match Order
Update    Add Tracking
Order     Link Email
    │
    ▼
┌─────────────────────────┐
│ ProductInfoFinderService│ ─── If no product URLs
└────────┬────────────────┘     Tavily search + AI extraction
         │
         ▼
SuggestCommodityCodesJob
```

### Image Extraction Flow

```
Email HTML
     │
     ▼
┌──────────────────────────┐
│ extract_product_images() │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Filter non-product images│ ─── Logos, icons, pixels, social
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Filter by size (<50px)   │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ Sort by size (largest    │
│ first = more likely      │
│ product image)           │
└────────┬─────────────────┘
         │
         ▼
Assign to order_items by position
         │
         ▼
If no images: Tavily fallback
```

## Testing/Verification

### Test Email Classification

```ruby
classifier = EmailClassifierService.new
result = classifier.classify(
  email_subject: "Your order #12345 is confirmed",
  email_body: "Thank you for your order...",
  from_address: "orders@retailer.com"
)
puts result[:email_type]  # => "order_confirmation"
puts result[:products]    # => [{name: "...", brand: "..."}]
```

### Test Image Extraction

```ruby
email = InboundEmail.last
parser = EmailParserService.new(email)
images = parser.extract_product_images
puts images  # => ["https://cdn.../product1.jpg", ...]
```

### Test Tracking URL Extraction (including Global-e)

```ruby
email = InboundEmail.find(10)
parser = EmailParserService.new(email)
tracking = parser.extract_tracking_urls
puts tracking  # => [{carrier: "global_e", url: "...", tracking_number: "LTN..."}]
```

### Test Product Info Finding

```ruby
finder = ProductInfoFinderService.new
info = finder.find(product_name: "Nike Air Max", retailer: "Nike")
puts info[:found]      # => true
puts info[:material]   # => "Leather, rubber"
puts info[:image_url]  # => "https://..."
```

### Test Email-Order Linking

```ruby
order = Order.find(8)
order.inbound_emails.count  # => 2 (confirmation + shipping)
order.inbound_emails.pluck(:subject)
# => ["Order #624274 confirmed", "Shipping update for order #624274"]
```

## Limitations & Future Improvements

### Current Limitations

1. **Image-product matching is positional** - Assumes images appear in same order as products in email. May mismatch if email layout is unusual.

2. **Redirect URL tracking** - Works for Global-e but may miss other redirect patterns.

3. **Tavily search rate limits** - Heavy usage may hit API limits.

4. **AI classification accuracy** - Claude Haiku is fast but may occasionally misclassify edge cases.

### Future Improvements

1. **Smarter image-product matching** - Use AI to match images to product descriptions.

2. **More carrier patterns** - Add patterns for international carriers.

3. **Caching for Tavily** - Cache product info to avoid repeated searches.

4. **Batch classification** - Process multiple emails in one API call.

5. **Email threading** - Detect email threads for better order matching.
