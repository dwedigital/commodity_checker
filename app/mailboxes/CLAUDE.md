# Mailboxes - AI Context

Action Mailbox integration for receiving forwarded emails via Resend.

## How It Works

1. User forwards email to `track-{token}@inbound.tariffik.com`
2. Resend receives email, POSTs to `/rails/action_mailbox/resend/inbound_emails`
3. Action Mailbox creates `ActionMailbox::InboundEmail` record
4. `ApplicationMailbox` routes based on recipient address
5. `TrackingMailbox` processes the email

## ApplicationMailbox

Routes emails to appropriate mailbox:

```ruby
routing /^track-/i => :tracking
```

Emails to `track-*@domain` go to TrackingMailbox.

## TrackingMailbox

Main mailbox for processing forwarded tracking emails.

**Flow:**
1. `before_processing :find_user` - Extract token, find user
2. `process` - Create InboundEmail record, queue job
3. `bounce_with_no_user` - Handle unknown tokens

**Token extraction:**
```ruby
# From: track-abc123@domain.com
# Extracts: abc123
extract_token("track-abc123@domain.com")
```

**Body extraction:**
- `extract_body_text` - Prefers plain text, falls back to HTML stripped of tags
- `extract_body_html` - Saves raw HTML for image extraction

**Creates InboundEmail with:**
- `subject`
- `from_address`
- `body_text` - Plain text version
- `body_html` - Raw HTML (for extracting product images)
- `processing_status` - :received

## Mail Object

The `mail` object is a `Mail::Message` instance:

```ruby
mail.to           # ["track-abc123@domain.com"]
mail.from         # ["sender@example.com"]
mail.subject      # "Your order has shipped"
mail.text_part    # Plain text part
mail.html_part    # HTML part
mail.body         # Raw body
mail.multipart?   # true/false
```

## Testing Locally

### Option 1: Test Emails Controller
Use the test emails controller at `/dashboard/test_emails/new` to paste email content.

### Option 2: Action Mailbox Conductor
```
http://localhost:3000/rails/conductor/action_mailbox/inbound_emails
```

### Option 3: ngrok for Real Emails
1. Start ngrok: `ngrok http 3000`
2. Set Resend webhook URL to ngrok URL + `/rails/action_mailbox/resend/inbound_emails`
3. Forward real emails to test

## Resend Configuration

See `docs/RESEND_SETUP.md` for full setup.

**Key config in `config/initializers/action_mailbox.rb`:**
```ruby
Rails.application.config.action_mailbox.resend_api_key = ENV["RESEND_API_KEY"]
Rails.application.config.action_mailbox.resend_webhook_secret = ENV["RESEND_WEBHOOK_SECRET"]
```

**Environment variables needed:**
- `RESEND_API_KEY` - API key from Resend dashboard
- `RESEND_WEBHOOK_SECRET` - Webhook signing secret
- `INBOUND_EMAIL_DOMAIN` - e.g., `inbound.tariffik.com`

## Adding New Mailboxes

1. Create `app/mailboxes/new_mailbox.rb`:
```ruby
class NewMailbox < ApplicationMailbox
  def process
    # Handle email
  end
end
```

2. Add routing in `ApplicationMailbox`:
```ruby
routing /^support-/i => :new
```

## Debugging

Check Action Mailbox records:
```ruby
ActionMailbox::InboundEmail.last
ActionMailbox::InboundEmail.last.mail  # Parsed mail object
```

View processing status:
```ruby
ActionMailbox::InboundEmail.pending
ActionMailbox::InboundEmail.processing
ActionMailbox::InboundEmail.delivered
ActionMailbox::InboundEmail.failed
```

Check our InboundEmail records:
```ruby
InboundEmail.last
InboundEmail.last.body_html.present?  # Should be true
InboundEmail.last.order               # Linked order (if any)
```
