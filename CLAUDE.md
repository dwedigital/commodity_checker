# CLAUDE.md - AI Assistant Context

This file provides context for AI assistants working on this codebase.

## Required: Implementation Documentation

After implementing any significant feature (new models, services, controllers, or major modifications to existing functionality), you MUST create an implementation summary markdown file at:

```
./claude/implementations/<feature-name>.md
```

Use `./claude/implementations/product-url-lookup-and-scraping.md` as the template. Each implementation doc must include:

- **Overview** - What was built and why
- **Design Decisions** - Key architectural choices made
- **Database Changes** - New tables, modified columns, migrations
- **New Files Created** - Table listing each new file and its purpose
- **Modified Files** - Table listing changes to existing files
- **Routes** - Any new routes added
- **Data Flow** - ASCII diagrams showing how data moves through the system
- **Testing/Verification** - Manual testing steps and verification commands
- **Limitations & Future Improvements** - Known issues and potential enhancements

Do this automatically at the end of implementing a feature - do not wait to be asked.

## Project Overview

**Commodity Code Checker** - A Rails 8 app that helps users track online orders and get EU/UK commodity tariff code suggestions. Users forward tracking emails, the app extracts order info, and uses Claude AI + UK Trade Tariff API to suggest HS codes.

## Key Architectural Decisions

### Why Rails 8?
- Solid Queue for background jobs (no Redis needed)
- Action Mailbox for email processing
- Hotwire for modern frontend without heavy JS

### Why SQLite in development?
- Zero setup, works immediately
- Production can use PostgreSQL

### Email Processing Flow
```
Email → Mailgun → Action Mailbox → TrackingMailbox → ProcessInboundEmailJob
                                                            ↓
                                        OrderMatcherService (find or create order)
                                                            ↓
                                        SuggestCommodityCodesJob (async)
```

### Commodity Code Flow
```
Product Description → TariffLookupService (UK API) → LlmCommoditySuggester (Claude)
                                                            ↓
                                                  Validate code exists
                                                            ↓
                                                  Save to OrderItem
```

## Important Files to Know

| File | Purpose |
|------|---------|
| `app/services/email_parser_service.rb` | Extracts tracking URLs, products, retailers from emails |
| `app/services/order_matcher_service.rb` | Matches emails to existing orders (avoid duplicates) |
| `app/services/tariff_lookup_service.rb` | UK Trade Tariff API client |
| `app/services/llm_commodity_suggester.rb` | Claude AI integration for code suggestions |
| `app/services/tracking_scraper_service.rb` | Scrapes carrier tracking pages |
| `app/services/product_scraper_service.rb` | Scrapes product pages for descriptions (with ScrapingBee fallback) |
| `app/mailboxes/tracking_mailbox.rb` | Routes inbound emails to users |
| `app/jobs/process_inbound_email_job.rb` | Main email processing orchestration |

## Common Tasks

### Adding a new carrier for tracking
1. Add URL pattern to `EmailParserService::TRACKING_PATTERNS`
2. Add handler to `TrackingScraperService::CARRIER_HANDLERS`
3. Implement `scrape_<carrier>` method

### Improving email parsing
- Edit `EmailParserService#extract_product_descriptions`
- Use multiple strategies, avoid overfitting to one email format
- Test with `/test_emails/new` interface

### Modifying commodity code suggestions
- Edit `LlmCommoditySuggester::SYSTEM_PROMPT` for different AI behavior
- The service combines tariff API results with Claude's interpretation

## Database Schema Summary

```
users (Devise auth + inbound_email_token)
  └── orders (retailer, reference, status)
        ├── order_items (description, suggested/confirmed codes)
        └── tracking_events (carrier, URL, status, location)
  └── inbound_emails (subject, from, body, processing_status)
```

## External APIs

### UK Trade Tariff API
- Base: `https://www.trade-tariff.service.gov.uk/api/v2/`
- No auth required
- Returns `fuzzy_match` or `exact_match` responses
- See `TariffLookupService#parse_search_results` for response handling

### Anthropic Claude API
- Used via `anthropic` gem
- Model: `claude-sonnet-4-20250514`
- Returns JSON with commodity_code, confidence, reasoning

## Testing Without External Services

1. **Without Mailgun**: Use `/test_emails/new` to paste email content
2. **Without Claude API**: Remove API key, suggestions will return nil
3. **Without Tariff API**: Service returns empty array on failure

## Gotchas and Quirks

1. **Email parsing is fragile**: Different retailers format emails differently. The parser uses multiple strategies but may need tuning.

2. **Tracking scraping limitations**: Many carrier sites (UPS, FedEx, Amazon) are JavaScript-heavy. The scraper notes when users should check directly.

3. **Order matching**: When multiple emails arrive for same order, `OrderMatcherService` tries to match by reference, tracking URL, or retailer+timeframe.

4. **Tariff API response formats**: The API returns different structures for `fuzzy_match` vs `exact_match`. Both are handled in `parse_search_results`.

5. **User email tokens**: Each user has a unique token like `track-abc123@domain`. The token is hex, generated on user creation.

## Running the App

```bash
# Development
bin/rails server

# With Tailwind watching (if needed)
bin/dev

# Background jobs (Solid Queue)
bin/rails solid_queue:start

# Console
bin/rails console
```

## Environment Variables

```
ANTHROPIC_API_KEY          # Required for commodity suggestions
INBOUND_EMAIL_DOMAIN       # e.g., inbound.yourdomain.com
MAILGUN_INGRESS_SIGNING_KEY # For webhook verification
SCRAPINGBEE_API_KEY        # Optional, for scraping protected websites (Cloudflare, etc.)
```

## Future Improvements (Not Yet Implemented)

- CSV export for confirmed codes
- Email notifications for delivery updates
- Better tracking scraper with headless browser
- Batch commodity code processing
- Order search/filtering
