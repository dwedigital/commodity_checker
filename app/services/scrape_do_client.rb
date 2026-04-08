# Centralized client for Scrape.do API
# Handles API token management, timeouts, and error handling
# Replaces ScrapingBee with scrape.do free tier
class ScrapeDoClient
  API_URL = "https://api.scrape.do/".freeze

  # Default timeouts for Scrape.do requests
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

  # Check if Scrape.do is configured
  def self.configured?
    api_token.present?
  end

  def self.api_token
    ENV["SCRAPE_DO_API_TOKEN"]
  end

  # Fetch a page using Scrape.do
  # @param url [String] The URL to fetch
  # @param options [Hash] Additional options:
  #   - super_proxy [Boolean] Use residential/mobile proxy (super=true) vs datacenter proxy
  #   - geo_code [String] Country code for proxy (e.g., "gb", "us", "de")
  #   - render [Boolean] Whether to render JavaScript (default: true)
  #   - custom_wait [Integer] Additional wait time in ms after page loads
  #   - wait_selector [String] CSS selector to wait for before returning
  # @return [Hash] { body: String, status: Integer, fetched_via: Symbol } on success
  #                { error: String } on failure
  def fetch(url, super_proxy: false, geo_code: "gb", render: true, custom_wait: nil, wait_selector: nil)
    token = self.class.api_token

    unless token.present?
      Rails.logger.warn("ScrapeDoClient: SCRAPE_DO_API_TOKEN not configured")
      return { error: "Scrape.do not configured" }
    end

    params = build_params(url, token, super_proxy: super_proxy, geo_code: geo_code,
                          render: render, custom_wait: custom_wait, wait_selector: wait_selector)

    proxy_type = super_proxy ? "super" : "standard"

    response = @conn.get(API_URL, params)

    if response.success?
      Rails.logger.info("ScrapeDoClient: #{proxy_type} proxy succeeded for #{url}")
      {
        body: response.body,
        status: response.status,
        fetched_via: super_proxy ? :scrape_do_super : :scrape_do
      }
    else
      error_msg = parse_error_response(response)
      Rails.logger.error("ScrapeDoClient: #{proxy_type} proxy failed for #{url}: #{error_msg}")
      { error: error_msg }
    end
  rescue Faraday::TimeoutError
    Rails.logger.error("ScrapeDoClient: Request timed out for #{url}")
    { error: "Scrape.do request timed out" }
  rescue Faraday::Error => e
    Rails.logger.error("ScrapeDoClient: Error for #{url}: #{e.message}")
    { error: "Scrape.do error: #{e.message}" }
  end

  private

  def build_params(url, token, super_proxy:, geo_code:, render:, custom_wait:, wait_selector:)
    params = {
      token: token,
      url: url,
      render: render.to_s,
      geoCode: geo_code
    }

    # Use super proxy (residential/mobile IPs) when needed
    params[:super] = "true" if super_proxy

    # Optional wait parameters for JS rendering
    params[:customWait] = custom_wait.to_i if custom_wait.present?
    params[:waitSelector] = wait_selector if wait_selector.present?

    params
  end

  def parse_error_response(response)
    error_msg = "Scrape.do HTTP #{response.status}"
    begin
      error_data = JSON.parse(response.body)
      error_msg = "Scrape.do: #{error_data['message']}" if error_data["message"]
    rescue JSON::ParserError
      # Use default error message
    end
    error_msg
  end
end
