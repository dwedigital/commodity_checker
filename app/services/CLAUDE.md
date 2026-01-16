# Services - AI Context

This directory contains service objects that encapsulate business logic.

## Service Overview

| Service | Purpose | External Dependencies |
|---------|---------|----------------------|
| `email_classifier_service.rb` | AI classification of email types | Anthropic Claude (Haiku) |
| `email_parser_service.rb` | Extract data from forwarded emails | None |
| `product_info_finder_service.rb` | Find product details via web search | Tavily API, Anthropic Claude |
| `product_url_finder_service.rb` | Find product pages on retailer sites | ScrapingBee (optional) |
| `order_matcher_service.rb` | Match emails to existing orders | None |
| `tariff_lookup_service.rb` | Query UK Trade Tariff API | UK Gov API |
| `llm_commodity_suggester.rb` | AI commodity code suggestions | Anthropic Claude |
| `tracking_scraper_service.rb` | Scrape carrier tracking pages | Carrier websites |

## EmailClassifierService

Uses Claude AI (Haiku model) to classify email types and extract product information.

**Email types classified:**
- `order_confirmation` - Purchase confirmed, contains products
- `shipping_notification` - Package shipped, may have tracking
- `delivery_confirmation` - Package delivered
- `return_confirmation` - Return/refund processed
- `marketing` - Promotional emails
- `other` - Doesn't fit categories

**Usage:**
```ruby
classifier = EmailClassifierService.new
result = classifier.classify(
  email_subject: "Your order is confirmed",
  email_body: "...",
  from_address: "orders@retailer.com"
)
# => { email_type: "order_confirmation", confidence: 0.95, products: [...], ... }
```

**Response format:**
```ruby
{
  email_type: "order_confirmation",
  confidence: 0.95,
  contains_products: true,
  products: [{ name: "...", brand: "...", color: "...", material: "..." }],
  retailer: "Retailer Name",
  order_reference: "12345",
  reasoning: "..."
}
```

## EmailParserService

Parses forwarded emails to extract:
- Tracking URLs (carrier-specific patterns)
- Order references
- Retailer name (from email domain or content)
- Product descriptions
- **Product images from HTML** (new)

**Key methods:**
- `parse` - Returns hash with all extracted data
- `extract_tracking_urls` - Finds carrier tracking links (including redirect URLs)
- `extract_product_descriptions` - Multiple strategies for finding products
- `extract_product_images` - Extracts product images from HTML body

**Supported carriers for tracking:**
Royal Mail, DHL, UPS, FedEx, USPS, Amazon, DPD, Hermes/Evri, Yodel, **Global-e**

**Image extraction features:**
- Filters out logos, icons, tracking pixels, social buttons
- Filters by size (skips images < 50px)
- Sorts by image size (larger = more likely product image)
- Returns up to 10 image URLs

**Strategies for product extraction:**
1. Lines before attribute markers (Color/Size/Qty)
2. Explicit patterns (bullet lists, "Items:" sections)
3. Quantity patterns ("2x Product Name")

**When modifying:** Avoid overfitting to specific email formats. Test with multiple retailer emails.

## ProductInfoFinderService

Uses Tavily web search + Claude AI to find detailed product information when emails don't contain product URLs.

**When used:**
- Email is an order confirmation
- Email contains products but no product URLs
- Need additional product details for commodity code classification

**Flow:**
1. Build search query from product name + retailer + brand
2. Search Tavily API (advanced search, includes images)
3. AI extracts product details from search results
4. Returns structured product info

**Usage:**
```ruby
finder = ProductInfoFinderService.new
info = finder.find(
  product_name: "Nike Air Max 90",
  retailer: "Nike",
  brand: "Nike"
)
# => { found: true, product_name: "...", material: "...", image_url: "...", ... }
```

**Response format:**
```ruby
{
  found: true,
  confidence: 0.85,
  product_name: "Full product name",
  brand: "Brand",
  category: "Footwear",
  material: "Leather upper, rubber sole",
  composition: "...",
  country_of_origin: "Vietnam",
  description: "...",
  product_url: "https://...",
  image_url: "https://...",
  key_features: ["..."]
}
```

## ProductUrlFinderService

Searches retailer websites to find product page URLs.

**Usage:**
```ruby
finder = ProductUrlFinderService.new
result = finder.find(
  retailer_name: "ASOS",
  product_name: "Black T-Shirt"
)
# => { url: "https://asos.com/product/...", search_url: "..." }
```

**Features:**
- Retailer-specific search URL patterns (Amazon, eBay, ASOS, etc.)
- Uses ScrapingBee for JS-rendered pages (if configured)
- Scores URLs by relevance to product name
- Filters to likely product URLs (not category/search pages)

## OrderMatcherService

Prevents duplicate orders when multiple emails arrive for same purchase.

**Matching strategies (in order):**
1. Same order reference number
2. Same tracking URL
3. Same retailer within 7 days

**Usage:**
```ruby
matcher = OrderMatcherService.new(user, parsed_email_data)
existing_order = matcher.find_matching_order
```

## TariffLookupService

Client for UK Trade Tariff API (`https://www.trade-tariff.service.gov.uk/api/v2/`).

**Key methods:**
- `search(query)` - Search for commodity codes by keyword
- `get_commodity(code)` - Get details for specific code
- `get_headings(chapter)` - Get headings for a chapter

**API Response Types:**
- `fuzzy_match` - Returns array of commodities in `goods_nomenclature_match`
- `exact_match` - Returns pointer to heading/commodity, requires follow-up request

**Error handling:** Returns empty array/nil on failure, logs errors.

## LlmCommoditySuggester

Combines tariff API with Claude AI for intelligent code suggestions.

**Flow:**
1. Search tariff API for initial suggestions
2. Build context with product description + API results
3. Query Claude with system prompt for classification expertise
4. Parse JSON response
5. Validate suggested code exists in tariff database

**System prompt** defines Claude's role as customs classification expert.

**Response format:**
```ruby
{
  commodity_code: "6405100000",
  confidence: 0.85,
  reasoning: "...",
  category: "Footwear",
  validated: true,
  official_description: "..."
}
```

## TrackingScraperService

Scrapes carrier tracking pages for delivery status.

**Carrier handlers:** Royal Mail, DHL, UPS, FedEx, Amazon, DPD, Evri, Yodel

**Limitations:**
- Many carriers use JavaScript-heavy pages
- Some require authentication (Amazon)
- Falls back to noting users should check directly

**Status normalization:**
Maps carrier-specific statuses to: `delivered`, `out_for_delivery`, `in_transit`, `processing`, `exception`

## Adding New Services

Follow the pattern:
1. Single responsibility
2. Initialize with dependencies
3. Public methods return data, don't save to DB
4. Handle errors gracefully, return nil/empty on failure
5. Log errors for debugging
