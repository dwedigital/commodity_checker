# Resend Setup for Inbound Email

This guide walks through setting up Resend to receive forwarded tracking emails.

## Overview

When users forward tracking emails to their unique address (e.g., `track-abc123@inbound.tariffik.com`), Resend receives them and forwards to your Rails app via the `actionmailbox-resend` gem.

## Step 1: Create Resend Account

1. Sign up at https://resend.com/
2. Verify your account and email

## Step 2: Add Your Domain

You'll need a subdomain for receiving emails (e.g., `inbound.tariffik.com`).

1. In Resend dashboard, go to **Domains**
2. Click **Add Domain**
3. Enter your subdomain: `inbound.tariffik.com`
4. Select your region

## Step 3: Configure DNS Records

Resend will provide DNS records to add. You need:

### MX Records (Required for receiving email)
```
Type: MX
Host: inbound (or inbound.tariffik.com)
Value: feedback-smtp.us-east-1.amazonses.com (or as specified by Resend)
Priority: 10
```

### TXT Records (For verification and SPF)
```
Type: TXT
Host: inbound
Value: v=spf1 include:amazonses.com ~all (or as specified by Resend)
```

### DKIM Records
Resend will provide CNAME records for DKIM verification. Add all records exactly as shown.

### Verify DNS
- After adding DNS records, click **Verify** in Resend dashboard
- DNS propagation can take up to 48 hours, but usually works within minutes

## Step 4: Enable Inbound Emails

**Important:** DNS verification alone is not enough - you must explicitly enable inbound for each domain.

1. In Resend dashboard, go to **Receiving**
2. Find your custom domain (e.g., `inbound.curlybrackets.tech`)
3. **Enable inbound** for the domain (there's a separate toggle/button)
4. Add the MX record Resend provides for receiving (separate from sending DNS records)
5. Configure email forwarding rules if needed

Note: The `.resend.app` addresses work automatically, but custom domains require this extra step.

## Step 5: Create Webhook Endpoint

1. Go to **Webhooks** in Resend dashboard
2. Click **Add Webhook**
3. Configure:

```
Endpoint URL: https://tariffik.com/rails/action_mailbox/resend/inbound_emails
Events: Select "email.received" (or all inbound email events)
```

4. Copy the **Signing Secret** (starts with `whsec_`) - you'll need this for `RESEND_WEBHOOK_SECRET`

**Important:** The endpoint URL must be your production domain with the Action Mailbox Resend endpoint.

## Step 6: Get API Key

1. Go to **API Keys** in Resend dashboard
2. Create a new API key (or use existing)
3. Copy the key (starts with `re_`) - you'll need this for `RESEND_API_KEY`

## Step 7: Set Environment Variables

In production (Render), set these environment variables:

```bash
# Required
INBOUND_EMAIL_DOMAIN=inbound.tariffik.com
RESEND_API_KEY=re_your-api-key
RESEND_WEBHOOK_SECRET=whsec_your-webhook-signing-secret
```

For Render:
1. Go to your service dashboard
2. Navigate to **Environment** tab
3. Add the environment variables above

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

3. Temporarily update Resend webhook to use ngrok URL:
   ```
   https://abc123.ngrok.io/rails/action_mailbox/resend/inbound_emails
   ```

4. Send a test email to `track-{your-token}@inbound.tariffik.com`

5. Check Rails logs for incoming email

### Production Testing

1. Deploy your app
2. Ensure Resend webhook points to production URL
3. Log in and find your unique email address on the dashboard
4. Forward a tracking email to that address
5. Check that an order is created

## Troubleshooting

### Emails not arriving

1. Check Resend dashboard → **Logs** for incoming emails
2. Verify DNS records are correctly configured
3. Check webhook is active and pointing to correct URL
4. Check Rails logs for Action Mailbox errors

### 401/403 Unauthorized errors

- Verify `RESEND_WEBHOOK_SECRET` is set correctly
- Check the signing secret matches the one in Resend dashboard
- Ensure webhook signature verification is working

### Emails arriving but not processed

1. Check Rails logs for mailbox routing issues
2. Verify the email address format matches `track-{token}@domain`
3. Check the user token exists in the database

### DNS Verification Failing

- Wait longer for propagation (up to 48 hours)
- Use `dig` to verify records:
  ```bash
  dig MX inbound.tariffik.com
  dig TXT inbound.tariffik.com
  ```

## Security Notes

1. **Webhook Secret**: Always verify Resend webhook signatures in production (handled by the gem via Svix)
2. **HTTPS**: Ensure your production site uses HTTPS
3. **Rate Limiting**: Consider adding rate limiting for the ingress endpoint

## Alternative: Development Testing Without Resend

For local development, use the built-in test email feature:

1. Visit `/dashboard/test_emails/new` in your browser
2. Paste email content to simulate forwarding
3. No Resend setup required for testing

## Cost

- Resend has a free tier that includes inbound emails
- Check https://resend.com/pricing for current limits

## Gem Information

This integration uses the `actionmailbox-resend` gem:
- GitHub: https://github.com/rcoenen/actionmailbox-resend
- Receives Resend webhooks
- Verifies signatures via Svix
- Reconstructs RFC822 MIME messages
- Delivers to ActionMailbox for processing
