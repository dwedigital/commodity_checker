# Tariffik

A Rails application for tracking online orders and suggesting EU/UK commodity tariff codes. Users forward tracking emails to the app, which extracts order/delivery info and suggests appropriate HS commodity codes using the UK Trade Tariff API combined with Claude AI.

**Website**: [tariffik.com](https://tariffik.com)

## Features

- **Email Forwarding**: Each user gets a unique email address to forward tracking emails
- **Email Parsing**: Extracts tracking URLs, order references, retailer info, and product descriptions
- **Order Tracking**: Scrapes carrier tracking pages for delivery status updates
- **Commodity Code Suggestions**: Uses UK Trade Tariff API + Claude AI to suggest HS codes
- **Code Confirmation**: Users can review and confirm suggested codes
- **CSV Export**: Export confirmed codes for customs declarations
- **Product URL Lookup**: Paste any product URL to get commodity code suggestions
- **Photo Lookup**: Upload product photos for AI-powered identification
- **Blog**: Markdown-based blog for SEO content about commodity codes
- **Premium API**: REST API for programmatic commodity code lookups (Starter+ plans)
- **Developer Dashboard**: API key management and usage monitoring at `/dashboard/developer`

## Tech Stack

- **Framework**: Rails 8.0 with Ruby 3.3+
- **Database**: SQLite (development) / PostgreSQL (production)
- **Frontend**: Hotwire (Turbo + Stimulus) + Tailwind CSS
- **Authentication**: Devise
- **Background Jobs**: Solid Queue
- **Email Processing**: Action Mailbox + Resend
- **AI**: Anthropic Claude API
- **Rate Limiting**: Rack::Attack
- **Markdown**: Redcarpet + Rouge (syntax highlighting)
- **Storage**: Cloudflare R2 (S3-compatible)
- **Hosting**: Render (with auto-deploy from GitHub)

## Getting Started

### Prerequisites

- Ruby 3.3+
- Node.js (for Tailwind CSS)
- SQLite3

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd tariffik

# Install dependencies
bundle install

# Setup database
bin/rails db:setup

# Start the server
bin/rails server
```

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Key variables:

- `ANTHROPIC_API_KEY` - For commodity code suggestions
- `INBOUND_EMAIL_DOMAIN` - Domain for receiving forwarded emails
- `RESEND_API_KEY` - For Resend API access
- `RESEND_WEBHOOK_SECRET` - For Resend webhook verification

### Running Tests

```bash
bin/rails test
```

## Architecture

### Core Models

- **User**: Authentication + unique inbound email token
- **Order**: Groups items from a single purchase
- **OrderItem**: Individual products with commodity codes
- **TrackingEvent**: Delivery tracking snapshots
- **InboundEmail**: Stored forwarded emails

### Key Services

- **EmailParserService**: Extracts data from forwarded emails
- **OrderMatcherService**: Matches new emails to existing orders
- **TariffLookupService**: Queries UK Trade Tariff API
- **LlmCommoditySuggester**: Claude AI for code suggestions
- **TrackingScraperService**: Fetches tracking status from carriers

### Background Jobs

- **ProcessInboundEmailJob**: Parses emails and creates/updates orders
- **SuggestCommodityCodesJob**: Gets AI suggestions for order items
- **UpdateTrackingJob**: Refreshes tracking status

## Email Flow

1. User forwards tracking email to `track-{token}@inbound.tariffik.com`
2. Resend receives and forwards to Action Mailbox endpoint
3. TrackingMailbox routes to correct user via token
4. ProcessInboundEmailJob parses email and creates/updates order
5. SuggestCommodityCodesJob queries tariff API + Claude for codes
6. User reviews suggestions on dashboard

## Premium API

Tariffik offers a REST API for programmatic commodity code lookups. API access requires a Starter subscription or higher.

### Authentication

All API requests require a Bearer token:

```bash
curl -X POST https://tariffik.com/api/v1/commodity-codes/suggest \
  -H "Authorization: Bearer tk_live_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"description": "Cotton t-shirt, blue"}'
```

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/commodity-codes/search?q=` | Search tariff codes |
| GET | `/api/v1/commodity-codes/:code` | Get code details |
| POST | `/api/v1/commodity-codes/suggest` | AI suggestion (sync) |
| POST | `/api/v1/commodity-codes/suggest-from-url` | AI from URL (async) |
| POST | `/api/v1/commodity-codes/batch` | Batch processing |
| GET | `/api/v1/batch-jobs/:id` | Poll batch status |
| GET | `/api/v1/usage` | Usage statistics |

### Rate Limits

| Tier | Requests/min | Requests/day | Batch Size |
|------|-------------|--------------|------------|
| Starter | 30 | 1,000 | 25 |
| Professional | 100 | 10,000 | 100 |
| Enterprise | 500 | Unlimited | 500 |

### Developer Dashboard

Manage API keys and monitor usage at `/dashboard/developer`. Free users see an upsell page.

### Postman Collection

Import `docs/Tariffik_API.postman_collection.json` for ready-to-use API requests.

## External API Integrations

### UK Trade Tariff API

- Base URL: `https://www.trade-tariff.service.gov.uk/api/v2/`
- No authentication required
- Used for searching and validating commodity codes

### Anthropic Claude API

- Used for interpreting product descriptions
- Suggests most appropriate HS codes with reasoning
- Requires API key in credentials/environment

### Resend

- Receives inbound emails via webhook
- See `docs/RESEND_SETUP.md` for configuration

## Development

### Testing Email Processing

Without Resend setup, use the test interface:

1. Visit `/dashboard/test_emails/new`
2. Paste email content
3. Submit to process

### Adding Carrier Support

Edit `app/services/tracking_scraper_service.rb`:

1. Add pattern to `CARRIER_HANDLERS`
2. Implement `scrape_<carrier>` method
3. Add URL patterns to `EmailParserService::TRACKING_PATTERNS`

## Blog

The site includes a file-based markdown blog at `/blog`. Posts are stored as markdown files in `content/blog/` with YAML front matter.

### Adding a Post

Create a file like `content/blog/my-post.md`:

```yaml
---
title: "My Post Title"
slug: my-post
date: 2026-01-17
description: "Brief description for SEO"
author: Tariffik Team
published: true
tags:
  - commodity-codes
---

Your markdown content here...
```

### Features
- GitHub-flavored markdown with syntax highlighting
- SEO meta tags (Open Graph, Twitter Cards, JSON-LD)
- Auto-generated sitemap at `/sitemap.xml`
- AI-friendly description at `/llms.txt`

## Deployment

The app is configured for deployment on Render with auto-deploy:

- `main` branch → Production (`tariffik.com`)
- `develop` branch → Staging (`tariffik-staging.onrender.com`)

### Key Considerations

1. Set all environment variables
2. Configure Resend domain and webhook
3. Run database migrations
4. Solid Queue runs inside Puma via plugin

### Puma Configuration

Puma auto-detects worker count based on available memory:
- 2GB RAM → 2-3 workers
- 4GB RAM → 6-7 workers

Override with `WEB_CONCURRENCY` env var if needed.

## License

MIT
