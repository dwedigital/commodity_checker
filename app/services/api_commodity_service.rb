class ApiCommodityService
  def initialize
    @llm_suggester = LlmCommoditySuggester.new
    @product_scraper = ProductScraperService.new
  end

  # Suggest commodity code from a text description
  # Returns hash with commodity_code, confidence, reasoning, etc.
  def suggest_from_description(description)
    return { error: "Description is required" } if description.blank?

    result = @llm_suggester.suggest(description)

    if result.nil?
      return { error: "Unable to suggest commodity code for this description" }
    end

    result
  end

  # Scrape a product URL and suggest commodity code
  # Returns hash with commodity_code, confidence, scraped_product, etc.
  def suggest_from_url(url)
    return { error: "URL is required" } if url.blank?

    # First scrape the product page
    scraped = @product_scraper.scrape(url)

    if scraped[:status] == :failed
      return {
        error: scraped[:error] || "Failed to scrape product page",
        url: url,
        fetch_attempts: scraped[:fetch_attempts]
      }.compact
    end

    # Build description from scraped data
    description = build_description_from_scraped(scraped)

    if description.blank?
      return {
        error: "Could not extract product information from URL",
        url: url,
        scraped_product: format_scraped_product(scraped)
      }
    end

    # Get commodity code suggestion
    result = @llm_suggester.suggest(description)

    if result.nil?
      return {
        error: "Unable to suggest commodity code for this product",
        url: url,
        scraped_product: format_scraped_product(scraped)
      }
    end

    # Merge scraped product data with suggestion
    result.merge(
      scraped_product: format_scraped_product(scraped)
    )
  end

  private

  def build_description_from_scraped(scraped)
    parts = []

    # Add title
    parts << scraped[:title] if scraped[:title].present?

    # Add brand
    parts << "Brand: #{scraped[:brand]}" if scraped[:brand].present?

    # Add material/composition
    parts << "Material: #{scraped[:material]}" if scraped[:material].present?

    # Add category
    parts << "Category: #{scraped[:category]}" if scraped[:category].present?

    # Add description (truncated)
    if scraped[:description].present?
      desc = scraped[:description].truncate(500)
      parts << desc unless desc == scraped[:title]
    end

    parts.join(". ")
  end

  def format_scraped_product(scraped)
    {
      title: scraped[:title],
      description: scraped[:description]&.truncate(500),
      brand: scraped[:brand],
      material: scraped[:material],
      category: scraped[:category],
      price: scraped[:price],
      currency: scraped[:currency],
      image_url: scraped[:image_url],
      retailer: scraped[:retailer_name],
      url: scraped[:url],
      fetched_via: scraped[:fetched_via],
      fetch_attempts: scraped[:fetch_attempts]
    }.compact
  end
end
