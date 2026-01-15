# Mailboxes - AI Context

Action Mailbox integration for receiving forwarded emails.

## How It Works

1. User forwards email to `track-{token}@inbound.yourdomain.com`
2. Mailgun receives email, POSTs to `/rails/action_mailbox/mailgun/inbound_emails/mime`
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
- Prefers plain text part
- Falls back to HTML with tags stripped
- Handles multipart emails

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

Without Mailgun, use the conductor UI:
```
http://localhost:3000/rails/conductor/action_mailbox/inbound_emails
```

Or use the test emails controller at `/test_emails/new`.

## Mailgun Configuration

See `docs/MAILGUN_SETUP.md` for full setup.

Key config in `config/environments/production.rb`:
```ruby
config.action_mailbox.ingress = :mailgun
```

Credentials needed:
- `MAILGUN_INGRESS_SIGNING_KEY` for webhook verification

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
