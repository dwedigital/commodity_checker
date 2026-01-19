# Centralized client for ScrapingBee API
# Handles API key management, timeouts, and error handling
class ScrapingbeeClient
  API_URL = "https://app.scrapingbee.com/api/v1/".freeze

  # Default timeouts for ScrapingBee requests
  DEFAULT_TIMEOUT = 60
  DEFAULT_OPEN_TIMEOUT = 30

  class NotConfiguredError < StandardError; end
  class RequestError < StandardError; end

  def initialize
    @conn = Faraday.new do |f|
      f.options.timeout = DEFAULT_TIMEOUT
      f.options.open_timeout = DEFAULT_OPEN_TIMEOUT
      f.adapter Faraday.default_adapter
    end
  end

  # Check if ScrapingBee is configured
  def self.configured?
    api_key.present?
  end

  def self.api_key
    ENV["SCRAPINGBEE_API_KEY"]
  end

  # Fetch a page using ScrapingBee
  # @param url [String] The URL to fetch
  # @param options [Hash] Additional options:
  #   - stealth [Boolean] Use stealth proxy (residential IPs, 75 credits) vs premium proxy (25 credits)
  #   - country_code [String] Country code for proxy (default: "gb")
  #   - render_js [Boolean] Whether to render JavaScript (default: true)
  #   - wait [String] Wait time in ms for JS to render (e.g., "3000")
  #   - wait_for [String] CSS selector to wait for (e.g., "a[href]")
  # @return [Hash] { body: String, status: Integer, fetched_via: Symbol } on success
  #                { error: String } on failure
  def fetch(url, stealth: false, country_code: "gb", render_js: true, wait: nil, wait_for: nil)
    api_key = self.class.api_key

    unless api_key.present?
      Rails.logger.warn("ScrapingbeeClient: SCRAPINGBEE_API_KEY not configured")
      return { error: "ScrapingBee not configured" }
    end

    params = build_params(url, api_key, stealth: stealth, country_code: country_code,
                          render_js: render_js, wait: wait, wait_for: wait_for)

    proxy_type = stealth ? "stealth" : "premium"

    response = @conn.get(API_URL, params)

    if response.success?
      Rails.logger.info("ScrapingbeeClient: #{proxy_type} proxy succeeded for #{url}")
      {
        body: response.body,
        status: response.status,
        fetched_via: stealth ? :scrapingbee_stealth : :scrapingbee
      }
    else
      error_msg = parse_error_response(response)
      Rails.logger.error("ScrapingbeeClient: #{proxy_type} proxy failed for #{url}: #{error_msg}")
      { error: error_msg }
    end
  rescue Faraday::TimeoutError
    Rails.logger.error("ScrapingbeeClient: Request timed out for #{url}")
    { error: "ScrapingBee request timed out" }
  rescue Faraday::Error => e
    Rails.logger.error("ScrapingbeeClient: Error for #{url}: #{e.message}")
    { error: "ScrapingBee error: #{e.message}" }
  end

  private

  def build_params(url, api_key, stealth:, country_code:, render_js:, wait:, wait_for:)
    params = {
      api_key: api_key,
      url: url,
      render_js: render_js.to_s,
      country_code: country_code
    }

    # Use either stealth_proxy (residential IPs, 75 credits) or premium_proxy (datacenter, 25 credits)
    if stealth
      params[:stealth_proxy] = "true"
    else
      params[:premium_proxy] = "true"
    end

    # Optional wait parameters for JS rendering
    params[:wait] = wait if wait.present?
    params[:wait_for] = wait_for if wait_for.present?

    params
  end

  def parse_error_response(response)
    error_msg = "ScrapingBee HTTP #{response.status}"
    begin
      error_data = JSON.parse(response.body)
      error_msg = "ScrapingBee: #{error_data['message']}" if error_data["message"]
    rescue JSON::ParserError
      # Use default error message
    end
    error_msg
  end
end
