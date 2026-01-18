# CORS configuration for Chrome extension API access
# Allows cross-origin requests from the browser extension

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Chrome extension origins use the chrome-extension:// protocol
    # The extension ID is generated when the extension is loaded
    # In development, use chrome-extension://* to allow any extension
    # In production, restrict to the specific published extension ID
    if Rails.env.production?
      # Replace with actual extension ID after publishing to Chrome Web Store
      extension_id = ENV.fetch("CHROME_EXTENSION_ID", "*")
      origins "chrome-extension://#{extension_id}"
    else
      # Allow any extension in development
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
    if Rails.env.production?
      extension_id = ENV.fetch("CHROME_EXTENSION_ID", "*")
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
