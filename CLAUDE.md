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

**Tariffik** ([tariffik.com](https://tariffik.com)) - A Rails 8 app that helps users track online orders and get EU/UK commodity tariff code suggestions. Users forward tracking emails, the app extracts order info, and uses Claude AI + UK Trade Tariff API to suggest HS codes.

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
Email → Resend → Action Mailbox → TrackingMailbox → ProcessInboundEmailJob
                                                            ↓
                                              EmailClassifierService (AI classification)
                                                            ↓
                                              EmailParserService (tracking URLs, images)
                                                            ↓
                                    ┌───────────────────────┴───────────────────────┐
                                    ▼                                               ▼
                          Order Confirmation                              Shipping/Delivery
                                    ↓                                               ↓
                      OrderMatcherService                               OrderMatcherService
                      (find or create order)                            (find matching order)
                                    ↓                                               ↓
                      ProductInfoFinderService                          Add tracking URLs
                      (Tavily search if no URLs)                        Link email to order
                                    ↓
                      SuggestCommodityCodesJob
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
| `app/services/email_classifier_service.rb` | AI classification of email types (order, shipping, etc.) |
| `app/services/email_parser_service.rb` | Extracts tracking URLs, products, images from emails |
| `app/services/product_info_finder_service.rb` | Tavily web search + AI to find product details |
| `app/services/order_matcher_service.rb` | Matches emails to existing orders (avoid duplicates) |
| `app/services/tariff_lookup_service.rb` | UK Trade Tariff API client |
| `app/services/llm_commodity_suggester.rb` | Claude AI integration for code suggestions |
| `app/services/tracking_scraper_service.rb` | Scrapes carrier tracking pages |
| `app/services/product_scraper_service.rb` | Scrapes product pages for descriptions (with ScrapingBee fallback) |
| `app/mailboxes/tracking_mailbox.rb` | Routes inbound emails to users, saves HTML body |
| `app/jobs/process_inbound_email_job.rb` | Main email processing orchestration with AI |

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

### AI Email Classification
The system uses AI to classify incoming emails and extract product information:

**Email Types:**
- `order_confirmation` - Purchase confirmed, contains products
- `shipping_notification` - Package shipped, may have tracking
- `delivery_confirmation` - Package delivered
- `return_confirmation` - Return/refund processed
- `marketing` - Promotional emails (ignored)
- `other` - Doesn't fit categories (ignored)

**Processing Logic:**
- Order confirmations with products → Create order, extract product images, suggest codes
- Shipping notifications → Match to existing order by reference, add tracking
- Delivery confirmations → Update order status

**Image Extraction:**
- Product images are extracted from email HTML
- Filters out logos, icons, tracking pixels, social buttons
- Falls back to Tavily web search if no images in email

## Database Schema Summary

```
users (Devise auth + inbound_email_token)
  └── orders (retailer, reference, status)
        ├── order_items (description, suggested/confirmed codes, image_url, product_url)
        ├── tracking_events (carrier, URL, status, location)
        └── inbound_emails (many - linked by order_id)
  └── inbound_emails (subject, from, body_text, body_html, processing_status, order_id)
```

**Key relationships:**
- `Order` has_many `inbound_emails` (all emails related to the order)
- `Order` belongs_to `source_email` (the email that created it)
- `InboundEmail` belongs_to `order` (linked by order reference number)
- `OrderItem` has `image_url` for product thumbnails

## External APIs

### UK Trade Tariff API
- Base: `https://www.trade-tariff.service.gov.uk/api/v2/`
- No auth required
- Returns `fuzzy_match` or `exact_match` responses
- See `TariffLookupService#parse_search_results` for response handling

### Anthropic Claude API
- Used via `anthropic` gem
- Model: `claude-sonnet-4-20250514` for commodity suggestions
- Model: `claude-3-haiku-20240307` for email classification (fast/cheap)
- Returns JSON with commodity_code, confidence, reasoning

### Tavily API (Web Search)
- Used for finding product details when email lacks product URLs
- Endpoint: `https://api.tavily.com/search`
- Returns search results with raw content and images
- Used by `ProductInfoFinderService`

### Resend (Inbound Email)
- Webhook endpoint: `/rails/action_mailbox/resend/inbound_emails`
- See `docs/RESEND_SETUP.md` for configuration

## Testing Without External Services

1. **Without Resend**: Use `/test_emails/new` to paste email content
2. **Without Claude API**: Remove API key, suggestions will return nil
3. **Without Tariff API**: Service returns empty array on failure

## Gotchas and Quirks

1. **Email parsing is fragile**: Different retailers format emails differently. The parser uses multiple strategies but may need tuning.

2. **Tracking scraping limitations**: Many carrier sites (UPS, FedEx, Amazon) are JavaScript-heavy. The scraper notes when users should check directly.

3. **Order matching**: When multiple emails arrive for same order, `OrderMatcherService` tries to match by reference, tracking URL, or retailer+timeframe.

4. **Tariff API response formats**: The API returns different structures for `fuzzy_match` vs `exact_match`. Both are handled in `parse_search_results`.

5. **User email tokens**: Each user has a unique token like `track-abc123@domain`. The token is hex, generated on user creation.

## Git Branching & Deployment Strategy

**IMPORTANT**: This app uses a feature branch → develop → production workflow.

### Branches
- `feature/*`, `bugfix/*`, `hotfix/*` → Feature branches for development
- `develop` → Auto-deploys to **staging** (`tariffik-staging.onrender.com`)
- `main` → Auto-deploys to **production** (`tariffik.com`)

### Branch Naming (Gitflow)
Use these prefixes for branch names:
- `feature/description` - New features (e.g., `feature/add-csv-export`)
- `bugfix/description` - Bug fixes (e.g., `bugfix/fix-image-urls`)
- `hotfix/description` - Urgent production fixes (e.g., `hotfix/fix-login-crash`)

### Workflow for All Changes
1. **Create feature branch** from `develop`:
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b feature/my-new-feature
   ```

2. **Make changes** and commit to your feature branch:
   ```bash
   git add .
   git commit -m "Description of changes"
   ```

3. **Test locally** - Verify changes work as expected

4. **Push branch** to remote:
   ```bash
   git push -u origin feature/my-new-feature
   ```

5. **Create PR** to `develop` and merge after confirmation:
   ```bash
   gh pr create --base develop --title "Feature: My new feature"
   gh pr merge --merge
   ```

6. **Test on staging** - Verify on `tariffik-staging.onrender.com`

7. **Deploy to production** - Create PR from `develop` → `main`:
   ```bash
   gh pr create --base main --head develop --title "Release: Description"
   gh pr merge --merge
   ```

### Hotfix Workflow (Urgent Production Fixes)
For critical bugs in production:
```bash
git checkout main
git pull origin main
git checkout -b hotfix/fix-critical-bug
# Make fix, commit, push
gh pr create --base main --title "Hotfix: Fix critical bug"
gh pr merge --merge
# Also merge to develop
git checkout develop
git merge main
git push origin develop
```

### Never
- Commit directly to `main` or `develop`
- Force push to `main`
- Deploy untested code to production
- Merge to `main` without testing on staging first

## Database Migrations - MUST BE BACKWARDS COMPATIBLE

**CRITICAL**: Migrations run BEFORE new code deploys. This means:
1. Migration runs on database
2. Old code briefly runs with new schema
3. New code starts

### Safe Migration Patterns ✅
```ruby
# Adding columns (with or without defaults)
add_column :products, :new_field, :string
add_column :products, :status, :integer, default: 0

# Relaxing constraints (NOT NULL → nullable)
change_column_null :products, :url, true

# Adding indexes
add_index :products, :new_field

# Adding new tables
create_table :new_things do |t|
  # ...
end
```

### Dangerous Migration Patterns ❌
```ruby
# Removing columns - old code may still reference them!
remove_column :products, :old_field  # ❌ DANGEROUS

# Renaming columns - old code uses old name!
rename_column :products, :old_name, :new_name  # ❌ DANGEROUS

# Adding NOT NULL without default - existing rows fail!
add_column :products, :required_field, :string, null: false  # ❌ DANGEROUS

# Changing column types - may lose data!
change_column :products, :count, :string  # ❌ DANGEROUS
```

### Safe Column Removal (2-step process)
1. **Release 1**: Deploy code that stops using the column
2. **Release 2**: Remove the column in migration

### Safe Column Rename (3-step process)
1. **Release 1**: Add new column, write to both old and new
2. **Release 2**: Migrate data, read from new, stop writing to old
3. **Release 3**: Remove old column

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
# Rails
RAILS_MASTER_KEY                   # For encrypted credentials
APP_HOST                           # tariffik.com (prod) or tariffik-staging.onrender.com (staging)

# Inbound Email (Resend)
INBOUND_EMAIL_DOMAIN               # inbound.tariffik.com
RESEND_API_KEY                     # For inbound email processing
RESEND_WEBHOOK_SECRET              # For webhook verification

# AI Services
ANTHROPIC_API_KEY                  # Required for commodity suggestions and email classification
TAVILY_API_KEY                     # For AI web search (product info from emails without URLs)

# Web Scraping
SCRAPINGBEE_API_KEY                # Optional, for scraping protected websites

# Cloudflare R2 Storage
CLOUDFLARE_R2_ACCESS_KEY_ID        # R2 API token access key
CLOUDFLARE_R2_SECRET_ACCESS_KEY    # R2 API token secret
CLOUDFLARE_R2_BUCKET               # tariffik-images
CLOUDFLARE_R2_ENDPOINT             # https://<account_id>.r2.cloudflarestorage.com
```

## Future Improvements (Not Yet Implemented)

- CSV export for confirmed codes
- Email notifications for delivery updates
- Better tracking scraper with headless browser
- Batch commodity code processing
- Order search/filtering
