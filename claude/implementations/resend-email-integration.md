# Resend Email Integration

## Overview

Migrated the inbound email processing from Mailgun to Resend using the `actionmailbox-resend` gem. This change allows the app to receive forwarded tracking emails via Resend's inbound email feature instead of Mailgun.

## Design Decisions

1. **actionmailbox-resend gem**: Chose this gem because it provides a drop-in replacement for Mailgun that integrates directly with Rails Action Mailbox
2. **Environment variable configuration**: Kept the same pattern of using env vars with Rails credentials fallback
3. **Mounted engine pattern**: The gem uses a Rails engine mounted at `/rails/action_mailbox/resend` instead of a built-in ingress

## Database Changes

None - the migration only affects configuration files.

## New Files Created

| File | Purpose |
|------|---------|
| `docs/RESEND_SETUP.md` | Complete setup guide for Resend inbound email |

## Modified Files

| File | Changes |
|------|---------|
| `Gemfile` | Added `actionmailbox-resend` gem |
| `config/routes.rb` | Mounted Resend engine at `/rails/action_mailbox/resend` |
| `config/environments/production.rb` | Removed Mailgun ingress configuration |
| `config/initializers/action_mailbox.rb` | Changed from Mailgun to Resend credentials |
| `.env.example` | Updated environment variables from Mailgun to Resend |
| `CLAUDE.md` | Updated all Mailgun references to Resend |
| `docs/CLAUDE.md` | Updated documentation reference |

## Deleted Files

| File | Reason |
|------|--------|
| `docs/MAILGUN_SETUP.md` | Replaced by `docs/RESEND_SETUP.md` |

## Routes

New route added via engine mount:
- `POST /rails/action_mailbox/resend/inbound_emails` - Webhook endpoint for Resend

## Data Flow

```
Email forwarded by user
        ↓
Resend receives email at inbound.yourdomain.com
        ↓
Resend sends webhook to /rails/action_mailbox/resend/inbound_emails
        ↓
actionmailbox-resend gem:
  - Verifies Svix signature using RESEND_WEBHOOK_SECRET
  - Fetches full email content using RESEND_API_KEY
  - Reconstructs RFC822 MIME message
  - Creates ActionMailbox::InboundEmail record
        ↓
ApplicationMailbox routes to TrackingMailbox (matches track-* pattern)
        ↓
TrackingMailbox:
  - Extracts user token from email address
  - Creates InboundEmail record in database
  - Queues ProcessInboundEmailJob
        ↓
ProcessInboundEmailJob processes email (unchanged from before)
```

## Environment Variables

**Required for production:**
```
INBOUND_EMAIL_DOMAIN=inbound.yourdomain.com
RESEND_API_KEY=re_your-api-key
RESEND_WEBHOOK_SECRET=whsec_your-signing-secret
```

## Testing/Verification

### Local Development
No Resend setup needed for local testing:
1. Start Rails server: `bin/dev`
2. Navigate to `/test_emails/new`
3. Paste email content to simulate forwarding
4. Verify order is created

### Production Setup
1. Create Resend account at resend.com
2. Add domain (e.g., `inbound.yourdomain.com`)
3. Configure DNS (MX records pointing to Resend)
4. Create webhook pointing to `https://yourdomain.com/rails/action_mailbox/resend/inbound_emails`
5. Set environment variables in Render
6. Forward test email to `track-{token}@inbound.yourdomain.com`
7. Verify order appears in dashboard

### Verify Installation
```bash
# Check gem is installed
bundle info actionmailbox-resend

# Check routes include Resend engine
bin/rails routes | grep resend
```

## Limitations & Future Improvements

- **No automatic bounce handling**: The current implementation logs unknown tokens but doesn't send bounce emails
- **Rate limiting**: Consider adding rate limiting to the webhook endpoint
- **Retry logic**: Resend has built-in retry for failed webhooks, but app-side retry logic could be added

## Resources

- [actionmailbox-resend gem](https://github.com/rcoenen/actionmailbox-resend)
- [Resend Inbound Documentation](https://resend.com/docs/dashboard/inbound)
- [Rails Action Mailbox Guide](https://guides.rubyonrails.org/action_mailbox_basics.html)
