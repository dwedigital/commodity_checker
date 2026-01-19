# Handles product lookup for guest (non-authenticated) users
# Performs synchronous scraping and commodity code suggestion
class GuestProductLookupService
  def initialize(url)
    @url = url
  end

  # Perform the lookup synchronously
  # @return [Hash] { scrape_result: Hash, suggestion: Hash } on success
  #                { error: String } on failure
  def call
    return { error: "URL is blank" } if @url.blank?

    # Scrape the product page
    scraper = ProductScraperService.new
    scrape_result = scraper.scrape(@url)

    # Get commodity code suggestion if scraping succeeded
    suggestion = nil
    if scrape_result[:status] == :completed || scrape_result[:status] == :partial
      description = build_description(scrape_result)

      if description.present?
        suggester = LlmCommoditySuggester.new
        suggestion = suggester.suggest(description)
      end
    end

    {
      scrape_result: scrape_result,
      suggestion: suggestion
    }
  end

  private

  # Build a description string from scraped product data
  def build_description(scrape_result)
    [
      scrape_result[:title],
      scrape_result[:description],
      scrape_result[:brand],
      scrape_result[:category],
      scrape_result[:material]
    ].compact.reject(&:blank?).join(". ")
  end
end
