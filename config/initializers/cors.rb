# CORS configuration for Chrome extension API access
# Allows cross-origin requests from the browser extension

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Chrome extension origins use the chrome-extension:// protocol
    # The extension ID is generated when the extension is loaded
    # In production with a specific extension ID set, restrict to that ID
    # Otherwise, allow any chrome extension (required for testing/staging)
    extension_id = ENV["CHROME_EXTENSION_ID"]
    if extension_id.present?
      origins "chrome-extension://#{extension_id}"
    else
      # Allow any extension (use regex for wildcard matching)
      origins(/chrome-extension:\/\/.*/)
    end

    resource "/api/v1/extension/*",
      headers: :any,
      methods: [ :get, :post, :delete, :options ],
      expose: [ "X-Request-Id" ],
      max_age: 86400
  end

  # Also allow the extension auth callback
  allow do
    extension_id = ENV["CHROME_EXTENSION_ID"]
    if extension_id.present?
      origins "chrome-extension://#{extension_id}"
    else
      origins(/chrome-extension:\/\/.*/)
    end

    resource "/extension/auth*",
      headers: :any,
      methods: [ :get, :post, :options ],
      max_age: 86400
  end
end
