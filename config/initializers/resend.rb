# frozen_string_literal: true

# Configure Resend for outbound email delivery
# API key is set via RESEND_API_KEY environment variable (already used for inbound email)

Resend.api_key = ENV["RESEND_API_KEY"]
