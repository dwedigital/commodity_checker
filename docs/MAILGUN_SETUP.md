# Mailgun Setup for Inbound Email

This guide walks through setting up Mailgun to receive forwarded tracking emails.

## Overview

When users forward tracking emails to their unique address (e.g., `track-abc123@inbound.yourdomain.com`), Mailgun receives them and forwards to your Rails app via Action Mailbox.

## Step 1: Create Mailgun Account

1. Sign up at https://www.mailgun.com/
2. Verify your account (may require payment info for sending, but receiving is included)

## Step 2: Add Your Domain

You'll need a subdomain for receiving emails (e.g., `inbound.yourdomain.com`).

1. In Mailgun dashboard, go to **Sending** → **Domains**
2. Click **Add New Domain**
3. Enter your subdomain: `inbound.yourdomain.com`
4. Select your region (EU or US)

## Step 3: Configure DNS Records

Mailgun will provide DNS records to add. You need:

### MX Records (Required for receiving email)
```
Type: MX
Host: inbound (or inbound.yourdomain.com)
Value: mxa.mailgun.org
Priority: 10

Type: MX
Host: inbound (or inbound.yourdomain.com)
Value: mxb.mailgun.org
Priority: 10
```

### TXT Records (For verification and sending)
```
Type: TXT
Host: inbound
Value: v=spf1 include:mailgun.org ~all

Type: TXT
Host: smtp._domainkey.inbound (or as specified by Mailgun)
Value: [DKIM key provided by Mailgun]
```

### Verify DNS
- After adding DNS records, click **Verify DNS Settings** in Mailgun
- DNS propagation can take up to 48 hours, but usually works within minutes

## Step 4: Create Mailgun Route

Routes tell Mailgun where to forward incoming emails.

1. Go to **Receiving** → **Routes** in Mailgun dashboard
2. Click **Create Route**
3. Configure:

```
Expression Type: Match Recipient
Recipient: .*@inbound.yourdomain.com

Actions:
  ✓ Forward: https://yourdomain.com/rails/action_mailbox/mailgun/inbound_emails/mime
  ✓ Store and notify (optional, for debugging)

Priority: 10
Description: Forward tracking emails to Rails app
```

**Important:** The forward URL must be your production domain with the Action Mailbox Mailgun endpoint.

## Step 5: Configure Rails Credentials

Add Mailgun credentials to your Rails app:

```bash
# Edit credentials
EDITOR="code --wait" bin/rails credentials:edit

# Or for production-specific credentials
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

Add:
```yaml
mailgun:
  api_key: "your-mailgun-api-key"
  signing_key: "your-mailgun-http-webhook-signing-key"

# Also set for Action Mailbox
action_mailbox:
  ingress_password: "your-secure-password-here"
```

### Finding Your Mailgun Keys

1. **API Key**: Mailgun Dashboard → Settings → API Keys → Private API Key
2. **Signing Key**: Mailgun Dashboard → Settings → API Keys → HTTP Webhook Signing Key

## Step 6: Set Environment Variables

In production, set these environment variables:

```bash
# Required
INBOUND_EMAIL_DOMAIN=inbound.yourdomain.com
MAILGUN_INGRESS_SIGNING_KEY=your-signing-key

# Optional (if not using credentials)
MAILGUN_API_KEY=your-api-key
```

For Heroku:
```bash
heroku config:set INBOUND_EMAIL_DOMAIN=inbound.yourdomain.com
heroku config:set MAILGUN_INGRESS_SIGNING_KEY=your-signing-key
```

## Step 7: Update Production Config

The app is already configured for Mailgun in `config/environments/production.rb`:
```ruby
config.action_mailbox.ingress = :mailgun
```

Update the mailer host:
```ruby
config.action_mailer.default_url_options = { host: "yourdomain.com" }
```

## Step 8: Test the Setup

### Local Testing (with ngrok)

1. Start your Rails server:
   ```bash
   bin/rails server
   ```

2. Start ngrok to expose your local server:
   ```bash
   ngrok http 3000
   ```

3. Update Mailgun Route to use ngrok URL:
   ```
   https://abc123.ngrok.io/rails/action_mailbox/mailgun/inbound_emails/mime
   ```

4. Send a test email to `track-{your-token}@inbound.yourdomain.com`

5. Check Rails logs for incoming email

### Production Testing

1. Deploy your app
2. Ensure Mailgun route points to production URL
3. Log in and find your unique email address on the dashboard
4. Forward a tracking email to that address
5. Check that an order is created

## Troubleshooting

### Emails not arriving

1. Check Mailgun dashboard → **Logs** for incoming emails
2. Verify DNS records are correctly configured
3. Check Mailgun Route is active and pointing to correct URL
4. Check Rails logs for Action Mailbox errors

### 401 Unauthorized errors

- Verify `MAILGUN_INGRESS_SIGNING_KEY` is set correctly
- Check the signing key matches the one in Mailgun dashboard

### Emails arriving but not processed

1. Check Rails logs for mailbox routing issues
2. Verify the email address format matches `track-{token}@domain`
3. Check the user token exists in the database

### DNS Verification Failing

- Wait longer for propagation (up to 48 hours)
- Use `dig` to verify records:
  ```bash
  dig MX inbound.yourdomain.com
  dig TXT inbound.yourdomain.com
  ```

## Security Notes

1. **Signing Key**: Always verify Mailgun webhook signatures in production
2. **HTTPS**: Ensure your production site uses HTTPS
3. **Rate Limiting**: Consider adding rate limiting for the ingress endpoint

## Alternative: Development Testing Without Mailgun

For local development, use the built-in test email feature:

1. Visit `/test_emails/new` in your browser
2. Paste email content to simulate forwarding
3. No Mailgun setup required for testing

## Cost

- Mailgun's free tier includes receiving emails
- Sending emails requires a paid plan (not needed for this app's core functionality)
