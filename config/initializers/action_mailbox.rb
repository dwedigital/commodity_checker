# Action Mailbox Configuration for Resend

# Resend API key for fetching full email content
# Set via environment variable or Rails credentials
Rails.application.config.action_mailbox.resend_api_key = \
  ENV["RESEND_API_KEY"] || \
  Rails.application.credentials.dig(:resend, :api_key)

# Resend webhook signing secret for verification (via Svix)
# Set via environment variable or Rails credentials
Rails.application.config.action_mailbox.resend_webhook_secret = \
  ENV["RESEND_WEBHOOK_SECRET"] || \
  Rails.application.credentials.dig(:resend, :webhook_secret)
