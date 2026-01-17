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

## Tech Stack

- **Framework**: Rails 8.0 with Ruby 3.3+
- **Database**: SQLite (development) / PostgreSQL (production)
- **Frontend**: Hotwire (Turbo + Stimulus) + Tailwind CSS
- **Authentication**: Devise
- **Background Jobs**: Solid Queue
- **Email Processing**: Action Mailbox + Resend
- **AI**: Anthropic Claude API

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

## API Integrations

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

1. Visit `/test_emails/new`
2. Paste email content
3. Submit to process

### Adding Carrier Support

Edit `app/services/tracking_scraper_service.rb`:

1. Add pattern to `CARRIER_HANDLERS`
2. Implement `scrape_<carrier>` method
3. Add URL patterns to `EmailParserService::TRACKING_PATTERNS`

## Deployment

The app is configured for deployment on Render. Key considerations:

1. Set all environment variables
2. Configure Resend domain and webhook
3. Run database migrations
4. Ensure Solid Queue is running for background jobs

## License

MIT
