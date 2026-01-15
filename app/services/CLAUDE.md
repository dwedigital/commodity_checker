# Services - AI Context

This directory contains service objects that encapsulate business logic.

## Service Overview

| Service | Purpose | External Dependencies |
|---------|---------|----------------------|
| `email_parser_service.rb` | Extract data from forwarded emails | None |
| `order_matcher_service.rb` | Match emails to existing orders | None |
| `tariff_lookup_service.rb` | Query UK Trade Tariff API | UK Gov API |
| `llm_commodity_suggester.rb` | AI commodity code suggestions | Anthropic Claude |
| `tracking_scraper_service.rb` | Scrape carrier tracking pages | Carrier websites |

## EmailParserService

Parses forwarded emails to extract:
- Tracking URLs (carrier-specific patterns)
- Order references
- Retailer name (from email domain or content)
- Product descriptions

**Key methods:**
- `parse` - Returns hash with all extracted data
- `extract_tracking_urls` - Finds carrier tracking links
- `extract_product_descriptions` - Multiple strategies for finding products

**Strategies for product extraction:**
1. Lines before attribute markers (Color/Size/Qty)
2. Explicit patterns (bullet lists, "Items:" sections)
3. Quantity patterns ("2x Product Name")

**When modifying:** Avoid overfitting to specific email formats. Test with multiple retailer emails.

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
