class PagesController < ApplicationController
  def home
  end

  def lookup
    url = params[:url]

    if url.blank?
      @error = "Please enter a product URL"
      return render partial: "pages/lookup_result", formats: [:html]
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

    render partial: "pages/lookup_result", formats: [:html]
  end
end
