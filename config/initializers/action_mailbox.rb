# Action Mailbox Configuration

# Mailgun signing key for webhook verification
# Set via environment variable or Rails credentials
Rails.application.config.action_mailbox.mailgun_signing_key = \
  ENV["MAILGUN_INGRESS_SIGNING_KEY"] || \
  Rails.application.credentials.dig(:mailgun, :signing_key)

# API key for Mailgun (if needed for additional features)
Rails.application.config.action_mailbox.mailgun_api_key = \
  ENV["MAILGUN_API_KEY"] || \
  Rails.application.credentials.dig(:mailgun, :api_key)
