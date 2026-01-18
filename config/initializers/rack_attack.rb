# Rate limiting configuration for API endpoints
# Uses Rack::Attack middleware to protect against abuse

class Rack::Attack
  # Use Rails cache as the backend
  Rack::Attack.cache.store = Rails.cache

  # Skip rate limiting in test environment
  Rack::Attack.enabled = !Rails.env.test?

  ### API Rate Limiting by API Key Tier ###

  # Throttle API requests by API key
  # Different limits apply based on tier (handled in discriminator)
  throttle("api/minute", limit: proc { |req| req.env["rack.attack.api_limit_minute"] || 5 },
                         period: 1.minute) do |req|
    if req.path.start_with?("/api/v1")
      req.env["rack.attack.api_key_identifier"]
    end
  end

  # Daily limit tracking (softer limit, enforced in controller)
  # This just tracks, controller enforces the actual limit
  track("api/daily") do |req|
    if req.path.start_with?("/api/v1")
      req.env["rack.attack.api_key_identifier"]
    end
  end

  ### Extension API Rate Limiting ###

  # Throttle anonymous extension lookups by extension_id (10/min)
  throttle("extension/anonymous", limit: 10, period: 1.minute) do |req|
    if req.path == "/api/v1/extension/lookup" && req.post?
      # Anonymous requests have extension_id in body
      unless req.get_header("HTTP_AUTHORIZATION")&.start_with?("Bearer ext_tk_")
        req.params["extension_id"]
      end
    end
  end

  # Throttle extension usage checks by IP (30/min)
  throttle("extension/usage", limit: 30, period: 1.minute) do |req|
    if req.path == "/api/v1/extension/usage" && req.get?
      req.ip
    end
  end

  # Throttle extension token exchange (5/min by IP)
  throttle("extension/token_exchange", limit: 5, period: 1.minute) do |req|
    if req.path == "/api/v1/extension/token" && req.post?
      req.ip
    end
  end

  # Throttle authenticated extension requests (varies by tier, handled by API key middleware)
  throttle("extension/authenticated", limit: proc { |req| req.env["rack.attack.extension_limit"] || 30 },
                                      period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/extension") && req.get_header("HTTP_AUTHORIZATION")&.start_with?("Bearer ext_tk_")
      req.env["rack.attack.extension_token_id"]
    end
  end

  ### General Protection ###

  # Block suspicious requests
  blocklist("block_bad_requests") do |req|
    # Block requests with suspicious SQL injection patterns
    req.query_string =~ /(\%27)|(\')|(\-\-)|(%23)|(#)/i ||
      req.path =~ /\.\./ # Path traversal
  end

  # Throttle general requests by IP (for non-API endpoints)
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/api/", "/assets/", "/up")
  end

  # Throttle login attempts
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.ip
    end
  end

  throttle("logins/email", limit: 5, period: 1.minute) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  ### Response Headers ###

  # Add rate limit headers to API responses
  ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
    req = payload[:request]

    if req.env["rack.attack.matched"] == "api/minute" && req.env["rack.attack.match_type"] == :throttle
      Rails.logger.warn("Rate limit exceeded for API key: #{req.env['rack.attack.api_key_identifier']}")
    end
  end

  ### Custom Responses ###

  # API rate limit exceeded response
  self.throttled_responder = lambda do |request|
    if request.path.start_with?("/api/")
      [
        429,
        {
          "Content-Type" => "application/json",
          "Retry-After" => request.env["rack.attack.match_data"][:period].to_s
        },
        [ {
          error: "rate_limit_exceeded",
          message: "Too many requests. Please slow down.",
          retry_after: request.env["rack.attack.match_data"][:period]
        }.to_json ]
      ]
    else
      [
        429,
        { "Content-Type" => "text/plain" },
        [ "Rate limit exceeded. Please try again later." ]
      ]
    end
  end

  # Blocked request response
  self.blocklisted_responder = lambda do |request|
    [
      403,
      { "Content-Type" => "application/json" },
      [ { error: "forbidden", message: "Request blocked." }.to_json ]
    ]
  end
end

# Middleware to extract API key and extension token for rate limits
class ApiKeyRateLimitMiddleware
  # Extension rate limits by user subscription tier
  EXTENSION_TIER_LIMITS = {
    free: 10,
    starter: 30,
    professional: 60,
    enterprise: 100
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.path.start_with?("/api/v1/extension")
      extract_extension_token_limits(request, env)
    elsif request.path.start_with?("/api/v1")
      extract_api_key_limits(request, env)
    end

    @app.call(env)
  end

  private

  def extract_api_key_limits(request, env)
    auth_header = request.get_header("HTTP_AUTHORIZATION")
    return unless auth_header&.start_with?("Bearer ")

    raw_key = auth_header.split(" ", 2).last
    api_key = ApiKey.authenticate(raw_key)

    if api_key
      env["rack.attack.api_key_identifier"] = "api_key:#{api_key.id}"
      env["rack.attack.api_limit_minute"] = api_key.requests_per_minute_limit
      env["rack.attack.api_key"] = api_key
    else
      # Unknown key gets lowest tier limit
      env["rack.attack.api_key_identifier"] = "api_key:unknown:#{raw_key[0, 15]}"
      env["rack.attack.api_limit_minute"] = 5
    end
  rescue => e
    Rails.logger.error("Error in API key rate limit middleware: #{e.message}")
  end

  def extract_extension_token_limits(request, env)
    auth_header = request.get_header("HTTP_AUTHORIZATION")
    return unless auth_header&.start_with?("Bearer ext_tk_")

    raw_token = auth_header.split(" ", 2).last
    ext_token = ExtensionToken.authenticate(raw_token)

    if ext_token
      tier = ext_token.user.subscription_tier.to_sym
      env["rack.attack.extension_token_id"] = "ext_token:#{ext_token.id}"
      env["rack.attack.extension_limit"] = EXTENSION_TIER_LIMITS[tier] || EXTENSION_TIER_LIMITS[:free]
      env["rack.attack.extension_token"] = ext_token
    else
      # Unknown token gets lowest limit
      env["rack.attack.extension_token_id"] = "ext_token:unknown:#{raw_token[0, 15]}"
      env["rack.attack.extension_limit"] = 5
    end
  rescue => e
    Rails.logger.error("Error in extension token rate limit middleware: #{e.message}")
  end
end

# Insert middleware before Rack::Attack
Rails.application.config.middleware.insert_before Rack::Attack, ApiKeyRateLimitMiddleware
