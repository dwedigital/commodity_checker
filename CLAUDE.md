# CLAUDE.md - AI Assistant Context

This file provides context for AI assistants working on this codebase.

## Required: Implementation Documentation

After implementing any significant feature (new models, services, controllers, or major modifications to existing functionality), you MUST create or update implementation documentation at:

```
./claude/implementations/<feature-name>.md
```

### When to Create vs Update

- **New feature**: Create a new implementation doc
- **Modifying existing feature**: Update the existing implementation doc if one exists (check `./claude/implementations/` first)
- **Bug fixes**: No doc needed unless it changes architecture or behavior significantly

### Finding Existing Docs

Before creating a new doc, check if one already exists:
```bash
ls ./claude/implementations/
```

### Template

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

## Brand Design System

**September 2026 refresh (current direction — use this for all new UI):** warm paper `#f8f7f2`, ink `#292725`, muted `#67645e`, hairline `#dddcd4`, red `#d93120`; Space Grotesk headings at weight 500 with tight tracking; mono uppercase eyebrows (`.tf-eyebrow`); 6px rounded-rectangle buttons (`.tf-button-primary/-dark/-outline`), never pills; sentence-case copy; shipping-label details. Commodity codes display as `6109 10 0010` with the subheading pair in red — use `commodity_code_display(code)` inside a `.tf-code` element. The north-east arrow is drawn, never typed: use the `tf_arrow` helper (or `.tf-logo-mark` / `--tf-arrow-mask` for marks and pseudo-elements). Never put U+2197 `↗` in markup or CSS `content` — no font the site loads has it, and it has an emoji presentation, so iOS renders it as a blue emoji.

| File | Role |
|------|------|
| `app/assets/stylesheets/tariffik.css` | Public site + shared shell (`tf-*`): nav, footer, homepage, live lookup result (`.tf-result`), limit panel (`.tf-limit`) |
| `app/assets/stylesheets/tariffik_workspace.css` | Signed-in workspace (`.tf-workspace`: page header, stats, panels, record lists, settings) and a **site-wide token remap** on `.tariffik-site` that maps the legacy Tailwind tokens below (`bg-primary`, `bg-brand-dark`, `bg-brand-mint`, `bg-highlight`, grays) onto the refresh palette |
| `app/views/shared/_page_header.html.erb` | Eyebrow + h1 + description + actions header for workspace pages |

Because of the token remap, legacy classes no longer render aubergine/bright-mint/yellow anywhere, but their *shapes* (pill badges, bold headings, Title Case) are still legacy. Don't write new markup with the legacy patterns below; migrate pages to `tf-*` when touching them. See `claude/implementations/home-page-quick-lookup.md`. Local preview uses fixed port **3101**.

### Legacy design system (pre-September 2026 — reference only)

The tables below describe the old retro palette. Keep them only to understand existing markup.

### Brand Colors

| Name | Hex | Tailwind Class | Usage |
|------|-----|----------------|-------|
| Primary (Red) | `#E3170A` | `bg-primary`, `text-primary`, `border-primary` | CTAs, active states, links, errors |
| Mint | `#A9E5BB` | `bg-brand-mint`, `text-brand-mint` | Success states, positive badges |
| Yellow/Highlight | `#FCF6B1` | `bg-highlight`, `text-highlight` | Warnings, pending states, info banners |
| Orange | `#F7B32B` | `bg-brand-orange`, `text-brand-orange` | Secondary actions, accents |
| Aubergine (Dark) | `#2D1E2F` | `bg-brand-dark`, `text-brand-dark` | Headers, high-contrast sections, table headers |

### Design Tokens (Tailwind v4)

Colors are defined in `app/assets/tailwind/application.css` using `@theme`:
```css
@theme {
  --color-primary: #E3170A;
  --color-primary-hover: #c91409;
  --color-brand-mint: #A9E5BB;
  --color-highlight: #FCF6B1;
  --color-brand-orange: #F7B32B;
  --color-brand-dark: #2D1E2F;
}
```

### Component Patterns

| Element | Pattern | Example |
|---------|---------|---------|
| Cards | `rounded-2xl` with `border border-gray-200` | Outer containers |
| Inner elements | `rounded-xl` | Form inputs, inner boxes |
| Buttons | `rounded-full` | All buttons |
| Form inputs | `rounded-xl border border-gray-200 py-2.5 px-4` | Text fields |
| Tables | `bg-brand-dark` header with `text-white` | High contrast |

### Status Badges

```erb
<%# Success/Complete %>
<span class="inline-flex items-center rounded-full bg-brand-mint px-3 py-1 text-sm font-medium text-brand-dark">Complete</span>

<%# Pending/Processing %>
<span class="inline-flex items-center rounded-full bg-highlight px-3 py-1 text-sm font-medium text-brand-dark">Pending</span>

<%# Error/Failed %>
<span class="inline-flex items-center rounded-full bg-primary/10 px-3 py-1 text-sm font-medium text-primary">Failed</span>
```

### Page Header Badges

Use colored badges above page titles for visual hierarchy:
```erb
<span class="inline-flex items-center rounded-full bg-brand-mint px-3 py-1 text-xs font-semibold text-brand-dark mb-2">SECTION NAME</span>
```

Color usage by context:
- **Mint** (`bg-brand-mint`) - Primary actions, getting started, success states
- **Highlight/Yellow** (`bg-highlight`) - Information, warnings
- **Orange** (`bg-brand-orange`) - Secondary actions, password/security
- **Aubergine** (`bg-brand-dark text-white`) - Settings, admin areas

### High-Contrast Tables

All dashboard tables use aubergine headers for readability:
```erb
<table class="min-w-full">
  <thead class="bg-brand-dark">
    <tr>
      <th class="px-4 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">Column</th>
    </tr>
  </thead>
  <tbody class="bg-white divide-y divide-gray-200">
    <tr>
      <td class="px-4 py-4 text-sm text-gray-900">Content</td>
    </tr>
  </tbody>
</table>
```

### Dark CTA Sections

For high-contrast call-to-action areas (e.g., upsells, feature promos):
```erb
<div class="bg-brand-dark rounded-2xl p-8 text-center">
  <h3 class="text-xl font-bold text-white mb-2">Heading</h3>
  <p class="text-gray-300 mb-6">Description text</p>
  <%= link_to "Action", path, class: "inline-flex items-center rounded-full bg-white px-6 py-3 text-sm font-semibold text-brand-dark hover:bg-gray-100 transition-colors" %>
</div>
```

### Stimulus Controllers for Interactivity

CSP blocks inline JavaScript. Use Stimulus controllers instead:
- `tabs_controller.js` - Tab switching with `border-primary` active state
- `clipboard_controller.js` - Copy to clipboard functionality
- `simple_chart_controller.js` - CSP-compliant Canvas-based line charts (used in analytics dashboard)

### Key Files for Styling

| File | Purpose |
|------|---------|
| `app/assets/tailwind/application.css` | Brand color definitions |
| `app/javascript/controllers/tabs_controller.js` | Tab active state styling |
| `app/views/shared/_navbar.html.erb` | Navigation styling |
| `app/views/layouts/application.html.erb` | Base layout |

## Key Architectural Decisions

### Why Rails 8?
- Solid Queue for background jobs (no Redis needed)
- Action Mailbox for email processing
- Hotwire for modern frontend without heavy JS

### Why PostgreSQL in development?
- Production parity with the production environment
- Full feature support (jsonb, GIN indexes, etc.)
- Docker Compose for local PostgreSQL (port 5444)
- SQLite fallback available with `USE_SQLITE=true` env var

### Authentication

Two ways in: an email and password, or Sign in with Google. A password signup
must confirm its address first (`allow_unconfirmed_access_for` is `0.days`, so
the verification step is real); a Google signup is confirmed on creation because
Google has already verified the address.

Two rules worth knowing before changing anything here:
- **Password reset refuses a Google-only account** and points at the Google
  button, so holding the inbox cannot create a password that walks past Google's
  own protections.
- **A signup cannot claim an address that already signs in with Google.** That
  person adds a password from account settings instead, while signed in.

`User#password_required?` and `#confirmation_required?` are overridden, because
`:validatable` wants a password from every new record and `:confirmable` would
otherwise hold a Google signup for an email it never needs. Google updates call
`skip_reconfirmation!`, or `:reconfirmable` parks a changed Google address in
`unconfirmed_email` and leaves the account on the old one.

Full detail in `claude/implementations/password-and-google-auth.md`.

```
/users/sign_in  (users/sessions#new, Google button only)
      │  POST /users/auth/google_oauth2
      ▼
Google consent  ──►  GET /users/auth/google_oauth2/callback
                            │
                            ▼
                  User.from_google_omniauth(auth)
                    ├─ refuses an unverified Google email
                    ├─ finds by provider + uid           (returning user)
                    ├─ else finds by email, links uid    (pre-Google account)
                    └─ else creates the user             (signup)
```

Signup CTAs point at `new_user_registration_path(source: "...")`; the source is
carried through the session and recorded on the `user_registered` event, because
a `?source=` param cannot survive the Google round trip.

**Gotcha:** the sign-in page is `app/views/users/sessions/new.html.erb`, not
`devise/sessions/new` — `Users::SessionsController` comes first in the view
lookup, so a file at the Devise path is silently ignored.

### MCP authorization (OAuth 2.1)

`/mcp` is an OAuth 2.1 resource server and Tariffik is its own authorization
server. API keys are **not** accepted at `/mcp`; they remain the credential for
`/api/v1`.

```
POST /mcp (no token) ──► 401 + WWW-Authenticate: Bearer resource_metadata="…"
   ├─ GET /.well-known/oauth-protected-resource[/mcp]   RFC 9728
   ├─ GET /.well-known/oauth-authorization-server[/mcp] RFC 8414
   ├─ POST /oauth/register                              RFC 7591, public clients
   ├─ GET  /oauth/authorize   PKCE S256 + `resource`, consent never skipped
   └─ POST /oauth/token       1h access token, rotating refresh token
```

Tokens are audience-bound (RFC 8707): `resource` rides from the authorize request
onto the grant and the token via Doorkeeper's `custom_access_token_attributes`,
and `/mcp` refuses a token issued for anything else.

**MCP is part of the free account.** What it is not is a way around the monthly
allowance: `lookup_from_url` and `lookup_from_description` check
`User#can_perform_lookup?`, so a lookup counts the same whether it came from the
website, the browser extension or an agent. `search_codes`, `get_code` and
`list_recent_lookups` are reads and are not metered.

**`ProductLookup` is the meter.** `lookups_this_month` counts those rows, so any
path that skips writing one also skips the allowance. Neither the MCP tools nor
`/api/v1/extension/lookup` let a caller opt out of being recorded, and they
should not be given the option back.

**Gotcha:** the consent forms must carry `data: { turbo: false }`. Turbo cannot
follow the cross-origin redirect back to a client's callback, so with Turbo
handling the submit the browser never leaves the consent page — and integration
tests do not catch it, because they do not run Turbo.

Full detail in `claude/implementations/mcp-oauth-authorization.md`.

**Gotcha:** Devise sets `OmniAuth.config.path_prefix` while evaluating
`devise_for`. Rails loads routes lazily under `rails test`, and the OmniAuth
middleware runs ahead of the router, so on a process's first request the prefix
is still nil and the request falls through to Devise's `passthru` as a 404.
`test/test_helper.rb` calls `Rails.application.reload_routes_unless_loaded` to
avoid this. Production eager-loads routes at boot, so it is not affected.

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

### Premium API Flow
```
┌─────────────────────────────────────────────────────────────────────┐
│                         API Gateway Layer                           │
├─────────────────────────────────────────────────────────────────────┤
│  Rack::Attack (rate limiting) → API Authentication → Controllers   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              ┌──────────┐   ┌──────────┐   ┌──────────┐
              │   Sync   │   │  Async   │   │  Batch   │
              │ Endpoint │   │ Endpoint │   │ Endpoint │
              └────┬─────┘   └────┬─────┘   └────┬─────┘
                   │              │              │
                   ▼              ▼              ▼
              ┌──────────────────────────────────────┐
              │         Existing Services            │
              │  TariffLookupService                 │
              │  LlmCommoditySuggester               │
              │  ProductScraperService               │
              └──────────────────────────────────────┘
                              │
                              ▼ (for async/batch)
              ┌──────────────────────────────────────┐
              │         Solid Queue Jobs             │
              │  ApiBatchProcessingJob               │
              │  ApiBatchItemJob                     │
              │  WebhookDeliveryJob                  │
              └──────────────────────────────────────┘
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
| `app/services/product_scraper_service.rb` | Scrapes product pages for descriptions (with Scrape.do fallback) |
| `app/services/blog_post_service.rb` | Loads and renders markdown blog posts with YAML front matter |
| `app/mailboxes/tracking_mailbox.rb` | Routes inbound emails to users, saves HTML body |
| `app/jobs/process_inbound_email_job.rb` | Main email processing orchestration with AI |
| `config/initializers/content_security_policy.rb` | CSP configuration for XSS protection |
| `config/initializers/secure_headers.rb` | Security headers (X-Frame-Options, etc.) |
| `app/controllers/api/v1/base_controller.rb` | API authentication, rate limiting, error handling |
| `app/controllers/api/v1/commodity_codes_controller.rb` | API endpoints for code search/suggest/batch |
| `app/controllers/developer_controller.rb` | Developer dashboard for API key management |
| `app/models/api_key.rb` | API key with tier, usage tracking, authentication |
| `app/services/api_commodity_service.rb` | Wraps scraper + suggester for API use |
| `config/initializers/rack_attack.rb` | Per-tier API rate limiting configuration |
| `app/controllers/admin/analytics_controller.rb` | Admin analytics dashboard with visitor/lookup/signup stats |
| `app/controllers/users/omniauth_callbacks_controller.rb` | Sign in with Google callback: finds or creates the user, refuses unverified emails |
| `app/controllers/users/sessions_controller.rb` | Sign-in page (Google button) and sign out |
| `app/controllers/users/accounts_controller.rb` | Account settings and account deletion |
| `config/initializers/doorkeeper.rb` | OAuth 2.1 authorization server configuration |
| `app/controllers/oauth/metadata_controller.rb` | RFC 8414 / RFC 9728 discovery documents |
| `app/controllers/oauth/registrations_controller.rb` | RFC 7591 dynamic client registration |

## Blog System

The site includes a file-based markdown blog for SEO content. No database required.

### Blog Architecture
```
content/blog/*.md          → Markdown files with YAML front matter
        ↓
BlogPostService            → Parses front matter, renders markdown
        ↓
BlogController             → index (list) and show (single post)
        ↓
/blog, /blog/:slug         → Public URLs
```

### Adding a Blog Post
1. Create a new `.md` file in `content/blog/`
2. Add YAML front matter:
```yaml
---
title: "Your Post Title"
slug: your-post-slug
date: 2026-01-17
description: "SEO description for the post"
author: Tariffik Team
published: true
tags:
  - commodity-codes
  - importing
---
```
3. Write content in markdown below the front matter
4. Optionally add hero images to `public/images/blog/`
5. Set `published: false` to keep as draft (visible in dev, hidden in production)

### Blog Features
- GitHub-flavored markdown with syntax highlighting (Rouge)
- SEO meta tags (Open Graph, Twitter Cards, JSON-LD)
- Reading time estimation
- Tag display
- Responsive design

## SEO & AI Agent Configuration

### robots.txt
Located at `public/robots.txt`. Allows all crawlers and references sitemap.

### sitemap.xml
Dynamic route at `/sitemap.xml` generated by `SitemapController`. Auto-includes:
- Static pages (home, blog, privacy, terms)
- All published blog posts with lastmod dates

### llms.txt
Located at `public/llms.txt`. Plain-text site description for AI agents/LLMs.
Follows the emerging llms.txt convention (like robots.txt but for AI).
Update this file when adding major features.

## Security Configuration

### Content Security Policy (CSP)
Configured in `config/initializers/content_security_policy.rb`. Protects against XSS attacks.

```
default-src 'self'; font-src 'self' data:; img-src 'self' https: http: data: blob: localhost;
object-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';
connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

Key protections:
- `script-src 'self'` - Only scripts from same origin (no inline JS allowed)
- `frame-ancestors 'none'` - Prevents clickjacking
- `object-src 'none'` - Blocks Flash/plugins
- `img-src` includes `blob:` for camera previews, `http:` and localhost for Active Storage

**Important:** CSP blocks inline JavaScript. Use Stimulus controllers instead of `onclick` handlers or `<script>` tags. See `tabs_controller.js` for an example.

**Troubleshooting:** If new functionality is blocked, check browser console for CSP errors. Enable report-only mode temporarily by uncommenting `config.content_security_policy_report_only = true`.

### Security Headers
Configured in `config/initializers/secure_headers.rb`.

| Header | Value | Purpose |
|--------|-------|---------|
| X-Frame-Options | DENY | Clickjacking protection |
| X-Content-Type-Options | nosniff | Prevent MIME sniffing |
| Referrer-Policy | strict-origin-when-cross-origin | Control referrer leakage |
| Permissions-Policy | camera=(self), others disabled | Control browser API access |

**Note:** `camera=(self)` is enabled for the Photo Lookup feature. HSTS is automatically added by Rails when `force_ssl = true`.

### Verification
```bash
# Check headers locally
bin/rails runner "puts Rails.application.config.content_security_policy.build(nil)"

# Check headers in production
curl -I https://tariffik.com | grep -E "(Content-Security|X-Frame|X-Content-Type)"
```

## Common Tasks

### Adding a new carrier for tracking
1. Add URL pattern to `EmailParserService::TRACKING_PATTERNS`
2. Add handler to `TrackingScraperService::CARRIER_HANDLERS`
3. Implement `scrape_<carrier>` method

### Improving email parsing
- Edit `EmailParserService#extract_product_descriptions`
- Use multiple strategies, avoid overfitting to one email format
- Test with `/dashboard/test_emails/new` interface

### Modifying commodity code suggestions
- Edit `LlmCommoditySuggester::SYSTEM_PROMPT` for different AI behavior
- The service combines tariff API results with Claude's interpretation

## Testing

### CRITICAL: Test Integrity Policy

**NEVER modify tests just to make them pass.** Tests define expected behavior. If a test fails:

1. **Assume the test is correct** - Tests were written to verify specific, intended behavior
2. **Fix the code, not the test** - The implementation should match the expected behavior
3. **Only modify a test if:**
   - The *requirements* have genuinely changed (confirmed by user)
   - The test itself has a bug (rare - investigate thoroughly first)
   - You're adding new test cases (not changing existing assertions)

**Why this matters:** Tests are the specification. Changing tests to match broken code defeats the purpose of testing and hides bugs.

### Test Strategy

This project uses a **hybrid testing approach**:

| API Type | Testing Method | Rationale |
|----------|---------------|-----------|
| UK Trade Tariff API | VCR cassettes | Deterministic, stable responses |
| Tavily Search API | VCR cassettes | Real search results, complex JSON |
| Web scraping | VCR cassettes | Captures real HTML for parsing |
| Anthropic Claude API | Mocks/stubs | LLM outputs are non-deterministic |

### Running Tests

```bash
# Run all tests
bin/rails test

# Run service tests only
bin/rails test test/services/

# Run a specific test file
bin/rails test test/services/email_parser_service_test.rb

# Run a specific test by line number
bin/rails test test/services/email_parser_service_test.rb:42
```

### Test Structure

```
test/
├── services/                    # Service unit tests
│   ├── tariff_lookup_service_test.rb
│   ├── email_parser_service_test.rb
│   ├── order_matcher_service_test.rb
│   └── llm_commodity_suggester_test.rb
├── cassettes/                   # VCR recorded API responses
│   ├── tariff_api/
│   ├── tavily/
│   └── scraping/
├── fixtures/
│   ├── llm_responses/           # JSON fixtures for Claude responses
│   └── *.yml                    # Rails model fixtures
└── support/
    ├── vcr_setup.rb             # VCR configuration
    └── llm_mock_helper.rb       # Helpers for mocking Claude API
```

### Writing Tests

**For VCR tests (external APIs):**
```ruby
test "searches tariff API" do
  with_cassette("tariff_api/search_tshirt") do
    results = @service.search("cotton t-shirt")

    # Assert structure, NOT specific content
    assert results.is_a?(Array)
    assert results.first.key?(:code)
  end
end
```

**For Claude API (use mocks):**
```ruby
test "suggests commodity code" do
  stub_commodity_suggestion(
    code: "6109100010",
    confidence: 0.85,
    reasoning: "Cotton t-shirt"
  )

  result = @suggester.suggest("Cotton t-shirt")

  assert_equal "6109100010", result[:commodity_code]
end
```

### Adding Tests for New Services

1. Create test file in `test/services/`
2. Use `with_cassette` for external HTTP calls
3. Use `stub_*` helpers for Claude API
4. Test error handling (API failures, invalid responses)
5. Test edge cases (empty input, malformed data)

See `test/CLAUDE.md` for detailed testing guidelines.

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

## Tiers

| | Free account | Business (starter/professional/enterprise) |
|---|---|---|
| Lookups | 5 a month, shared across web, extension and MCP | More; `can_perform_lookup?` is unlimited above free |
| MCP | Yes | Yes |
| Email forwarding, photo lookup, history, CSV | Yes | Yes |
| API keys and batch | No | Yes (`has_api_access?`) |

"Business" is a display name only. The `subscription_tier` enum is still
`free/starter/professional/enterprise`, so nothing had to be migrated.

Signed-out visitors get **one** demo lookup on the homepage
(`PagesController::GUEST_LOOKUP_LIMIT`). That is deliberately not a tier and is
not on the pricing page.

**Known inconsistency:** `User::EXTENSION_LOOKUP_LIMITS` still caps `starter` at
100 extension lookups a month while `can_perform_lookup?` gives paid accounts
unlimited web and MCP lookups. Worth reconciling before the pricing page ever
claims a number.

## Database Schema Summary

```
users (Google OAuth: provider/uid + inbound_email_token + subscription_tier)
  ├── oauth_applications (MCP clients, self-registered)
  │     ├── oauth_access_grants (PKCE challenge, resource)
  │     └── oauth_access_tokens (resource-bound, rotating refresh)
  ├── orders (retailer, reference, status)
  │     ├── order_items (description, suggested/confirmed codes, image_url, product_url)
  │     ├── tracking_events (carrier, URL, status, location)
  │     └── inbound_emails (many - linked by order_id)
  ├── inbound_emails (subject, from, body_text, body_html, processing_status, order_id)
  ├── api_keys (key_prefix, key_digest, tier, usage tracking)
  │     └── api_requests (endpoint, status_code, response_time_ms)
  ├── batch_jobs (status, total_items, webhook_url)
  │     └── batch_job_items (description/url, status, result)
  └── webhooks (url, secret, events, enabled)
```

**Key relationships:**
- `Order` has_many `inbound_emails` (all emails related to the order)
- `Order` belongs_to `source_email` (the email that created it)
- `InboundEmail` belongs_to `order` (linked by order reference number)
- `OrderItem` has `image_url` for product thumbnails
- `User` has_many `api_keys` (API authentication)
- `ApiKey` has_many `api_requests` (usage logging)
- `User` has_many `webhooks` (webhook delivery URLs)

## External APIs

### UK Trade Tariff API
- Base: `https://www.trade-tariff.service.gov.uk/api/v2/`
- No auth required
- Returns `fuzzy_match` or `exact_match` responses
- See `TariffLookupService#parse_search_results` for response handling

### Anthropic Claude API
- Used via `anthropic` gem
- Model: `claude-sonnet-5` for commodity suggestions and product-image vision (`thinking` disabled to preserve the small `max_tokens` budget for JSON output)
- Model: `claude-haiku-4-5` for email classification and product-info extraction (fast/cheap)
- Returns JSON with commodity_code, confidence, reasoning

### Tavily API (Web Search)
- Used for finding product details when email lacks product URLs
- Endpoint: `https://api.tavily.com/search`
- Returns search results with raw content and images
- Used by `ProductInfoFinderService`

### Resend (Inbound Email)
- Webhook endpoint: `/rails/action_mailbox/resend/inbound_emails`
- See `docs/RESEND_SETUP.md` for configuration

## Premium API

Tariffik offers a REST API for programmatic commodity code lookups at `/api/v1/`. Requires Starter subscription or higher.

### Authentication
All API requests require a Bearer token: `Authorization: Bearer tk_live_...`

### Key Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/commodity-codes/search?q=` | Search tariff codes |
| GET | `/api/v1/commodity-codes/:code` | Get code details |
| POST | `/api/v1/commodity-codes/suggest` | AI suggestion (sync) |
| POST | `/api/v1/commodity-codes/suggest-from-url` | AI from URL (async) |
| POST | `/api/v1/commodity-codes/batch` | Batch processing |
| GET | `/api/v1/batch-jobs/:id` | Poll batch status |
| GET | `/api/v1/usage` | Usage statistics |

### Rate Limits by Tier

| Tier | Requests/min | Requests/day | Batch Size |
|------|-------------|--------------|------------|
| Trial | 5 | 50 | 5 |
| Starter | 30 | 1,000 | 25 |
| Professional | 100 | 10,000 | 100 |
| Enterprise | 500 | Unlimited | 500 |

### Developer Dashboard
- Route: `/dashboard/developer`
- Free users see upsell page
- Subscribers see usage stats, API key management, recent requests

### API Key Management (Console)
```ruby
# Create API key
user = User.find_by(email: "user@example.com")
api_key = user.api_keys.create!(name: "My Key", tier: :starter)
puts api_key.raw_key  # Only shown once!

# Revoke key
api_key.revoke!
```

See `claude/implementations/api-layer-premium-feature.md` for full implementation details.

## Testing Without External Services

1. **Without Resend**: Use `/dashboard/test_emails/new` to paste email content
2. **Without Claude API**: Remove API key, suggestions will return nil
3. **Without Tariff API**: Service returns empty array on failure

## Gotchas and Quirks

1. **Email parsing is fragile**: Different retailers format emails differently. The parser uses multiple strategies but may need tuning.

2. **Tracking scraping limitations**: Many carrier sites (UPS, FedEx, Amazon) are JavaScript-heavy. The scraper notes when users should check directly.

3. **Order matching**: When multiple emails arrive for same order, `OrderMatcherService` tries to match by reference, tracking URL, or retailer+timeframe.

4. **Tariff API response formats**: The API returns different structures for `fuzzy_match` vs `exact_match`. Both are handled in `parse_search_results`.

5. **User email tokens**: Each user has a unique token like `track-abc123@domain`. The token is hex, generated on user creation.

## Git Branching & Deployment Strategy

**IMPORTANT**: This app uses a feature branch → develop → production workflow with GitHub Actions CI/CD.

### Infrastructure

| Environment | URL | Server | Deploys From |
|-------------|-----|--------|--------------|
| Production | https://tariffik.com | Hetzner VPS (116.203.77.140) | `main` branch |

See `claude/implementations/hetzner-infrastructure-deployment.md` for full deployment documentation.

### GitHub Actions Workflows

| Workflow | File | Trigger | What It Does |
|----------|------|---------|--------------|
| CI | `ci.yml` | PRs, push to `main` | Runs security scans, linting, and tests |
| Deploy Production | `deploy-production.yml` | Push to `main` | Runs tests, deploys to production |

### Branches
- `feature/*`, `bugfix/*`, `hotfix/*` → Feature branches for development
- `develop` → Integration branch
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

6. **Deploy to production** - Create PR from `develop` → `main`:
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

### Manual Deployments (Kamal)
You can still deploy manually from your local machine:
```bash
kamal deploy -d production   # Deploy to production
```
Requires `.kamal/secrets.production` locally.

### Never
- Commit directly to `main` or `develop`
- Force push to `main`
- Deploy untested code to production

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

### Prerequisites

Start PostgreSQL via Docker (uses port 5444 to avoid conflicts):
```bash
docker compose up -d          # Start PostgreSQL
docker compose down           # Stop PostgreSQL
docker compose logs postgres  # View logs
```

### Initial Setup (Fresh Clone)

```bash
docker compose up -d              # Start PostgreSQL
bin/rails db:create db:migrate    # Create and migrate database
bin/rails db:schema:load:queue    # Create Solid Queue tables
bin/rails db:seed                 # Create admin user (dev only)
bin/rails analytics:seed          # Optional: seed 90 days of mock analytics
```

### Development Commands

```bash
# Development (RECOMMENDED - runs Tailwind watcher)
bin/dev

# Alternative: Rails server only (Tailwind won't rebuild for new classes)
bin/rails server

# Background jobs (Solid Queue)
bin/rails solid_queue:start

# Console
bin/rails console

# Seed mock analytics data (for testing dashboard)
bin/rails analytics:seed
bin/rails analytics:clear
```

**Important**: Always use `bin/dev` in development. It runs both Rails and the Tailwind CSS watcher via Procfile.dev. Using `bin/rails server` alone means new Tailwind utility classes won't be compiled.

**SQLite fallback**: Set `USE_SQLITE=true` env var to use SQLite instead of PostgreSQL (no Docker required).

### Default Admin User (Development)

Created by `db:seed`:
- Email: `dave@dwedigital.com`
- Password: generated and printed by the seed. Set `SEED_ADMIN_PASSWORD` to choose your own.
- Or sign in with Google using the same address.

## Admin Dashboards

Admin-only routes require `user.admin? == true` (Devise authentication).

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| Analytics | `/admin/analytics` | Privacy-first analytics: visitors, lookups, sign-ups, usage trends |
| Solid Queue | `/admin/jobs` | Monitor background jobs, retry failed jobs, view recurring schedules |
| PgHero | `/admin/pghero` | PostgreSQL monitoring (production only) |

### Analytics Dashboard

Privacy-first analytics using Ahoy (no third-party services, no cookies). Features:
- Visitors over time with date range selection (7d/30d/90d/1y)
- Lookups by source (homepage guest/user, extension, photo upload, email forwarding)
- Sign-up tracking and conversion rates
- Active/repeat user metrics
- Top referrers and device breakdown

See `claude/implementations/ahoy-analytics.md` for implementation details.

### Solid Queue Dashboard

Provided by `mission_control-jobs` gem. Features:
- View pending, running, and failed jobs
- Retry or discard failed jobs
- Monitor recurring job schedules
- Queue health metrics

### Recurring Jobs

Configured in `config/recurring.yml`:

| Job | Schedule | Purpose |
|-----|----------|---------|
| `clear_solid_queue_finished_jobs` | Hourly | Prevent queue table bloat |
| `cleanup_orphaned_emails` | 3am daily | Delete orphaned inbound emails older than 30 days |

## Production Configuration (Render)

### Puma Workers
Puma auto-detects worker count based on available memory in production:
- Reads `/proc/meminfo` to get total RAM
- Reserves 512MB for system, allocates 512MB per worker
- Caps at 8 workers maximum

Override with `WEB_CONCURRENCY` env var if needed.

| RAM | Workers |
|-----|---------|
| 1GB | 1 |
| 2GB | 2-3 |
| 4GB | 6-7 |

### Deployment
- `main` branch auto-deploys to production (`tariffik.com`)
- Puma runs with `preload_app!` for copy-on-write memory savings

## Environment Variables

```
# Rails
RAILS_MASTER_KEY                   # For encrypted credentials
APP_HOST                           # tariffik.com

# Authentication (required - Sign in with Google is the only way in)
GOOGLE_CLIENT_ID                   # OAuth 2.0 Web application client
GOOGLE_CLIENT_SECRET               # Redirect URI: <host>/users/auth/google_oauth2/callback

# Puma (Production)
WEB_CONCURRENCY                    # Optional: Override auto-detected worker count
RAILS_MAX_THREADS                  # Threads per worker (default: 3)

# Inbound Email (Resend)
INBOUND_EMAIL_DOMAIN               # inbound.tariffik.com
RESEND_API_KEY                     # For inbound email processing
RESEND_WEBHOOK_SECRET              # For webhook verification

# AI Services
ANTHROPIC_API_KEY                  # Required for commodity suggestions and email classification
TAVILY_API_KEY                     # For AI web search (product info from emails without URLs)

# Web Scraping
SCRAPE_DO_API_TOKEN                # Optional, for scraping protected websites

# Cloudflare R2 Storage
CLOUDFLARE_R2_ACCESS_KEY_ID        # R2 API token access key
CLOUDFLARE_R2_SECRET_ACCESS_KEY    # R2 API token secret
CLOUDFLARE_R2_BUCKET               # tariffik-images
CLOUDFLARE_R2_ENDPOINT             # https://<account_id>.r2.cloudflarestorage.com
```

## Future Improvements (Not Yet Implemented)

- Email notifications for delivery updates
- Better tracking scraper with headless browser
- Order search/filtering
- Blog pagination (when post count exceeds 10-12)
- Blog tag filtering and archive pages
- RSS/Atom feed for blog
- API documentation page with interactive examples
- Stripe integration for subscription payments
