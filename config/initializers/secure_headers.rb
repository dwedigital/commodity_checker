# Be sure to restart your server when you modify this file.

# Configure security headers for all responses.
# These headers provide defense-in-depth against common web vulnerabilities.

Rails.application.config.action_dispatch.default_headers = {
  # Prevent clickjacking by disallowing the site from being embedded in frames
  "X-Frame-Options" => "DENY",

  # Prevent browsers from MIME-type sniffing (reduces XSS risk)
  "X-Content-Type-Options" => "nosniff",

  # Control how much referrer information is sent with requests
  # strict-origin-when-cross-origin: send full URL for same-origin, only origin for cross-origin
  "Referrer-Policy" => "strict-origin-when-cross-origin",

  # Disable browser features that aren't needed (reduces attack surface)
  "Permissions-Policy" => "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
}

# Note: Strict-Transport-Security (HSTS) is automatically added by Rails
# when config.force_ssl = true in production.rb. Rails sets:
# Strict-Transport-Security: max-age=31536000; includeSubDomains
#
# X-XSS-Protection is deprecated and not recommended by modern browsers.
# CSP provides better XSS protection.
