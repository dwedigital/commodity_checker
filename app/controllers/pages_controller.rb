class PagesController < ApplicationController
  GUEST_LOOKUP_LIMIT = 3
  GUEST_LOOKUP_WINDOW_HOURS = 168  # 1 week

  before_action :set_guest_lookup_data, only: [:home, :lookup]

  def home
  end

  def lookup
    url = params[:url]

    if url.blank?
      @error = "Please enter a product URL"
      return render partial: "pages/lookup_result", formats: [:html]
    end

    # Check rate limit for guest users
    unless user_signed_in?
      if @guest_lookup_count >= GUEST_LOOKUP_LIMIT
        @error = "You've reached your free lookup limit. Sign up for unlimited lookups!"
        @limit_reached = true
        return render partial: "pages/lookup_result", formats: [:html]
      end
    end

    # Scrape the product page
    scraper = ProductScraperService.new
    @scrape_result = scraper.scrape(url)

    # Get commodity code suggestion if scraping succeeded
    if @scrape_result[:status] == :completed || @scrape_result[:status] == :partial
      description = [
        @scrape_result[:title],
        @scrape_result[:description],
        @scrape_result[:brand],
        @scrape_result[:category],
        @scrape_result[:material]
      ].compact.reject(&:blank?).join(". ")

      if description.present?
        suggester = LlmCommoditySuggester.new
        @suggestion = suggester.suggest(description)
      end
    end

    # Record the lookup for guest users (after successful scrape)
    unless user_signed_in?
      record_guest_lookup(url: url, lookup_type: "url")
    end

    render partial: "pages/lookup_result", formats: [:html]
  end

  private

  def set_guest_lookup_data
    return if user_signed_in?

    # Get or create guest token
    @guest_token = cookies.signed[:guest_token]
    if @guest_token.blank?
      @guest_token = SecureRandom.uuid
      cookies.signed[:guest_token] = {
        value: @guest_token,
        expires: GUEST_LOOKUP_WINDOW_HOURS.hours.from_now,
        httponly: true,
        same_site: :lax
      }
    end

    # Get current lookup count from database
    @guest_lookup_count = GuestLookup.count_for_token(@guest_token, window_hours: GUEST_LOOKUP_WINDOW_HOURS)
    @guest_lookups_remaining = [GUEST_LOOKUP_LIMIT - @guest_lookup_count, 0].max
  end

  def record_guest_lookup(url:, lookup_type:)
    GuestLookup.create!(
      guest_token: @guest_token,
      lookup_type: lookup_type,
      url: url,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500)
    )

    # Update the count after recording
    @guest_lookup_count += 1
    @guest_lookups_remaining = [GUEST_LOOKUP_LIMIT - @guest_lookup_count, 0].max
  end
end
