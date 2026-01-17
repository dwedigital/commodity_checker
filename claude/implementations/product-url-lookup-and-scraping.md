# Product URL Lookup & Scraping Implementation

**Date:** 2026-01-16
**Feature:** Direct product URL lookup and automatic product link extraction from emails

## Overview

This implementation adds two new capabilities to Tariffik:

1. **Direct Product URL Lookup** - Users can paste a product page URL at `/product_lookups/new` to get commodity code suggestions without forwarding an email
2. **Email Product Link Enhancement** - Product URLs found in forwarded order emails are automatically extracted and scraped to get richer product descriptions for better commodity code suggestions

## Design Decisions

- **Standalone lookups**: Direct lookups don't require creating orders (can add to order later)
- **Automatic email scraping**: Product URLs in emails are scraped automatically in background jobs
- **Graceful fallback**: When scraping fails, partial data is shown and users are notified to check manually
- **Structured data first**: Scraping prioritizes JSON-LD and Open Graph meta tags over HTML parsing

## Database Changes

### New Table: `product_lookups`

```ruby
create_table :product_lookups do |t|
  t.references :user, null: false, foreign_key: true
  t.references :order_item, foreign_key: true, null: true

  # Input
  t.string :url, null: false
  t.string :retailer_name

  # Scraped data
  t.string :title
  t.text :description
  t.string :brand
  t.string :category
  t.string :price
  t.string :currency
  t.string :material
  t.string :image_url
  t.json :structured_data

  # Status
  t.integer :scrape_status, default: 0  # pending, completed, failed, partial
  t.text :scrape_error
  t.datetime :scraped_at

  # Commodity code (for standalone lookups)
  t.string :suggested_commodity_code
  t.decimal :commodity_code_confidence, precision: 5, scale: 4
  t.text :llm_reasoning
  t.string :confirmed_commodity_code

  t.timestamps
end
```

### Modified Table: `order_items`

```ruby
add_column :order_items, :product_url, :string
add_column :order_items, :scraped_description, :text
add_reference :order_items, :product_lookup, foreign_key: true
```

## New Files Created

### Models

| File | Purpose |
|------|---------|
| `app/models/product_lookup.rb` | ProductLookup model with scrape status enum, URL validation, and helper methods |

### Services

| File | Purpose |
|------|---------|
| `app/services/product_scraper_service.rb` | Scrapes product pages using JSON-LD, Open Graph, meta tags, and HTML fallback. Supports 15+ retailers. |
| `app/services/product_url_extractor_service.rb` | Extracts product URLs from text (emails). Patterns for Amazon, eBay, ASOS, John Lewis, Argos, Currys, Etsy, AliExpress, etc. |

### Jobs

| File | Purpose |
|------|---------|
| `app/jobs/scrape_product_page_job.rb` | Background job that scrapes product URLs and triggers LLM commodity code suggestion. Handles both ProductLookup and OrderItem records. |

### Controllers

| File | Purpose |
|------|---------|
| `app/controllers/product_lookups_controller.rb` | RESTful controller with `new`, `create`, `show`, `index`, `confirm_commodity_code`, and `add_to_order` actions |

### Views

| File | Purpose |
|------|---------|
| `app/views/product_lookups/new.html.erb` | URL input form with retailer info |
| `app/views/product_lookups/show.html.erb` | Display scraped product data and commodity code suggestion |
| `app/views/product_lookups/index.html.erb` | Table listing past lookups with status badges |
| `app/views/product_lookups/_product_lookup.html.erb` | Partial for Turbo Stream live updates |
| `app/views/product_lookups/create.turbo_stream.erb` | Turbo Stream response for async create |

### Migrations

| File | Purpose |
|------|---------|
| `db/migrate/20260116124500_create_product_lookups.rb` | Creates product_lookups table |
| `db/migrate/20260116124501_add_product_url_to_order_items.rb` | Adds product_url and scraped_description to order_items |

## Modified Files

### Models

| File | Change |
|------|--------|
| `app/models/user.rb` | Added `has_many :product_lookups, dependent: :destroy` |
| `app/models/order_item.rb` | Added `belongs_to :product_lookup, optional: true` and `enhanced_description` method |

### Services

| File | Change |
|------|--------|
| `app/services/email_parser_service.rb` | Added `extract_product_urls` method that delegates to ProductUrlExtractorService |

### Jobs

| File | Change |
|------|--------|
| `app/jobs/process_inbound_email_job.rb` | Added `schedule_product_scraping` to queue ScrapeProductPageJob for product URLs found in emails |
| `app/jobs/suggest_commodity_codes_job.rb` | Uses `item.enhanced_description` (scraped description if available, otherwise original) |

### Routes & Navigation

| File | Change |
|------|--------|
| `config/routes.rb` | Added `resources :product_lookups` with member routes for `confirm_commodity_code` and `add_to_order` |
| `app/views/layouts/application.html.erb` | Added "Lookup" link to main navigation |

## Routes

```
GET    /product_lookups                    product_lookups#index
POST   /product_lookups                    product_lookups#create
GET    /product_lookups/new                product_lookups#new
GET    /product_lookups/:id                product_lookups#show
POST   /product_lookups/:id/confirm_commodity_code
POST   /product_lookups/:id/add_to_order
```

## Data Flow

### Direct Product Lookup Flow

```
User pastes URL at /product_lookups/new
           │
           ▼
ProductLookupsController#create
           │
           ├─── Save ProductLookup (status: pending)
           │
           └─── ScrapeProductPageJob.perform_later
                        │
                        ▼
              ProductScraperService.scrape(url)
                        │
                        ▼
              Update ProductLookup with scraped data
                        │
                        ▼
              LlmCommoditySuggester.suggest(combined_description)
                        │
                        ▼
              Update ProductLookup with suggestion
                        │
                        ▼
              Broadcast Turbo Stream update to user
```

### Email Processing Flow (Enhanced)

```
Email arrives via Action Mailbox
           │
           ▼
ProcessInboundEmailJob
           │
           ├─── EmailParserService.parse
           │         └─── extract_product_urls (NEW)
           │
           ├─── Create Order + OrderItems
           │
           ├─── SuggestCommodityCodesJob (uses email description)
           │
           └─── schedule_product_scraping (NEW)
                        │
                        ▼
              For each product_url matched to an item:
                        │
                        ▼
              ScrapeProductPageJob.perform_later(order_item_id:)
                        │
                        ▼
              ProductScraperService.scrape(url)
                        │
                        ▼
              Update OrderItem.scraped_description
                        │
                        ▼
              Re-run LLM suggestion with enhanced description
```

## Scraping Strategy

The `ProductScraperService` extracts product data in this priority order:

1. **JSON-LD** (`<script type="application/ld+json">`) - Most reliable, structured Product schema
2. **Open Graph** (`<meta property="og:*">`) - Good for title, description, image
3. **Twitter Cards** (`<meta name="twitter:*">`) - Fallback for social metadata
4. **Standard Meta Tags** (`<meta name="description">`, `<title>`)
5. **HTML Parsing** - Last resort, looks for common CSS classes like `.product-title`, `.product-description`

### Supported Retailers

Explicit URL patterns for:
- Amazon (all regions)
- eBay
- ASOS
- John Lewis
- Argos
- Currys
- Very
- Next
- Etsy
- AliExpress
- Wayfair

Generic patterns catch most other e-commerce sites with `/product/` or `/item/` URLs.

## Testing

### Manual Testing Steps

1. Start the server: `bin/dev`
2. Sign in and go to "Lookup" in the navigation
3. Paste a product URL (e.g., Amazon product page)
4. Wait for scraping to complete and commodity code suggestion
5. Click "Confirm this code" to confirm
6. Optionally click an order to add the product to it

### Verification Commands

```bash
# Check routes
bin/rails routes | grep product

# Check model columns
bin/rails runner "puts ProductLookup.column_names"

# Test URL extraction
bin/rails runner "
  text = 'https://www.amazon.co.uk/dp/B08N5WRWNW'
  extractor = ProductUrlExtractorService.new(text)
  puts extractor.extract.inspect
"

# Test scraper (dry run)
bin/rails runner "
  scraper = ProductScraperService.new
  puts scraper.detect_retailer('https://www.amazon.co.uk/dp/B08N5WRWNW')
"
```

## ScrapingBee Fallback (Added 2026-01-16)

The scraper now uses ScrapingBee as a fallback for protected websites that block direct HTTP requests.

### How It Works

1. **Try direct fetch first** - Fast and free, works for most sites
2. **Detect failures** - HTTP 403, 401, 503, timeouts, connection failures
3. **Fallback to ScrapingBee** - Only if API key is configured and error is recoverable
4. **Return result** - Includes `fetched_via` field showing `:direct` or `:scrapingbee`

### Configuration

Add to `.env`:
```bash
SCRAPINGBEE_API_KEY=your-api-key-here
```

### ScrapingBee Settings

```ruby
params = {
  api_key: api_key,
  url: url,
  render_js: "true",       # Handle JavaScript SPAs
  premium_proxy: "true",   # Better success rate
  country_code: "gb"       # UK proxy for UK content
}
```

### Supported Protected Sites

Now works with:
- **Lululemon** - Previously returned 403
- **ProDirect Sport** - Previously timed out
- Other Cloudflare/bot-protected sites

### Cost Optimization

- Direct fetch is always attempted first (free)
- ScrapingBee only used for failures (pay-per-request)
- Premium proxy + JS rendering uses ~25 credits per request

### Bug Fix

Also fixed image URL handling where JSON-LD `image` field could be an array:
```ruby
image = json_ld_data&.dig("image")
image = image.first if image.is_a?(Array)
image = image["url"] if image.is_a?(Hash) && image["url"]
```

## Limitations & Future Improvements

### Current Limitations

- **Rate limiting**: No explicit rate limiting implemented yet. Relies on Solid Queue job processing.
- **URL matching**: Product URLs in emails are matched to order items sequentially, not by content similarity.
- **ScrapingBee costs**: Premium proxy + JS rendering uses credits; monitor usage

### Potential Future Improvements

1. **Image analysis**: Use Claude's vision to analyze product images for better classification
2. **Browser extension**: Quick lookups while browsing
3. **Bulk import**: CSV upload of multiple product URLs
4. **Caching**: Cache scrape results for same URL within a timeframe
5. **Smarter URL-to-item matching**: Use text similarity to match product URLs to the correct order items

## Files Summary

### New Files (12)
- `app/models/product_lookup.rb`
- `app/services/product_scraper_service.rb`
- `app/services/product_url_extractor_service.rb`
- `app/jobs/scrape_product_page_job.rb`
- `app/controllers/product_lookups_controller.rb`
- `app/views/product_lookups/new.html.erb`
- `app/views/product_lookups/show.html.erb`
- `app/views/product_lookups/index.html.erb`
- `app/views/product_lookups/_product_lookup.html.erb`
- `app/views/product_lookups/create.turbo_stream.erb`
- `db/migrate/20260116124500_create_product_lookups.rb`
- `db/migrate/20260116124501_add_product_url_to_order_items.rb`

### Modified Files (7)
- `app/models/user.rb`
- `app/models/order_item.rb`
- `app/services/email_parser_service.rb`
- `app/jobs/process_inbound_email_job.rb`
- `app/jobs/suggest_commodity_codes_job.rb`
- `config/routes.rb`
- `app/views/layouts/application.html.erb`
