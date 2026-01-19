class ProductUrlFinderService
  # Common search URL patterns for retailers
  SEARCH_PATTERNS = {
    # pattern => lambda that builds search URL
    default: ->(domain, query) { "https://#{domain}/search?q=#{ERB::Util.url_encode(query)}" },
    query_param: ->(domain, query) { "https://#{domain}/search?query=#{ERB::Util.url_encode(query)}" },
    term_param: ->(domain, query) { "https://#{domain}/search?term=#{ERB::Util.url_encode(query)}" },
    pages_search: ->(domain, query) { "https://#{domain}/pages/search-results?q=#{ERB::Util.url_encode(query)}" }
  }.freeze

  # Retailer-specific search URL builders
  RETAILER_SEARCH_URLS = {
    "amazon" => ->(domain, query) { "https://www.#{domain}/s?k=#{ERB::Util.url_encode(query)}" },
    "ebay" => ->(domain, query) { "https://www.#{domain}/sch/i.html?_nkw=#{ERB::Util.url_encode(query)}" },
    "asos" => ->(_, query) { "https://www.asos.com/search/?q=#{ERB::Util.url_encode(query)}" },
    "etsy" => ->(_, query) { "https://www.etsy.com/search?q=#{ERB::Util.url_encode(query)}" },
    "johnlewis" => ->(_, query) { "https://www.johnlewis.com/search?search-term=#{ERB::Util.url_encode(query)}" },
    "argos" => ->(_, query) { "https://www.argos.co.uk/search/#{ERB::Util.url_encode(query)}/" },
    "currys" => ->(_, query) { "https://www.currys.co.uk/search?q=#{ERB::Util.url_encode(query)}" }
  }.freeze

  def initialize
    @conn = Faraday.new do |f|
      f.options.timeout = 15
      f.options.open_timeout = 10
      f.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      f.headers["Accept"] = "text/html,application/xhtml+xml"
      f.response :follow_redirects, limit: 3
      f.adapter Faraday.default_adapter
    end

    @scrapingbee = ScrapingbeeClient.new
  end

  # Find product URL given retailer info and product name
  # Returns { url: "...", confidence: 0.8 } or nil
  def find(retailer_name:, retailer_domain: nil, product_name:)
    return nil if product_name.blank?

    domain = retailer_domain || derive_domain(retailer_name)
    return nil if domain.blank?

    Rails.logger.info("ProductUrlFinderService: Searching #{domain} for '#{product_name}'")

    # Clean up product name for search
    search_query = clean_search_query(product_name)

    # Try retailer-specific search first
    search_url = build_search_url(retailer_name, domain, search_query)

    # Fetch search results page
    html = fetch_search_page(search_url)
    return nil unless html

    # Extract product URLs from search results
    product_url = extract_best_product_url(html, domain, product_name)

    if product_url
      Rails.logger.info("ProductUrlFinderService: Found product URL: #{product_url}")
      { url: product_url, search_url: search_url }
    else
      Rails.logger.info("ProductUrlFinderService: No product URL found for '#{product_name}'")
      nil
    end
  rescue => e
    Rails.logger.error("ProductUrlFinderService error: #{e.message}")
    nil
  end

  private

  def derive_domain(retailer_name)
    return nil if retailer_name.blank?

    # Clean up retailer name and try common TLDs
    name = retailer_name.downcase
                        .gsub(/[^a-z0-9]/, "")

    # Try to detect if it's already a domain
    return retailer_name if retailer_name.match?(/\.[a-z]{2,}$/i)

    # Common patterns
    "#{name}.com"
  end

  def clean_search_query(product_name)
    # Remove color/size info that might be too specific
    query = product_name.dup
    query = query.gsub(/\s*-\s*Color:.*$/i, "")
    query = query.gsub(/\s*-\s*Size:.*$/i, "")
    query = query.gsub(/\s*-\s*Material:.*$/i, "")
    query.strip
  end

  def build_search_url(retailer_name, domain, query)
    # Check for retailer-specific pattern
    retailer_key = retailer_name&.downcase&.gsub(/[^a-z]/, "")

    if retailer_key && RETAILER_SEARCH_URLS[retailer_key]
      return RETAILER_SEARCH_URLS[retailer_key].call(domain, query)
    end

    # Default search URL pattern
    SEARCH_PATTERNS[:default].call(domain, query)
  end

  def fetch_search_page(url)
    # Most e-commerce sites need JS rendering - try ScrapingBee first if available
    if ScrapingbeeClient.configured?
      result = @scrapingbee.fetch(url, wait: "3000", wait_for: "a[href]")
      return result[:body] if result[:body] && has_product_content?(result[:body])
    end

    # Fallback to direct fetch (works for simpler sites)
    response = @conn.get(url)
    return response.body if response.success? && has_product_content?(response.body)

    nil
  rescue Faraday::Error => e
    Rails.logger.warn("ProductUrlFinderService: Failed to fetch #{url}: #{e.message}")
    nil
  end

  def has_product_content?(html)
    # Check if the page has actual product links (not just a JS shell)
    html.scan(/href=["'][^"']*["']/i).length > 20
  end

  def extract_best_product_url(html, domain, product_name)
    # Find all product-like links
    product_urls = extract_product_links(html, domain)
    return nil if product_urls.empty?

    # Score URLs by relevance to product name
    scored_urls = product_urls.map do |url|
      score = calculate_relevance_score(url, product_name)
      { url: url, score: score }
    end

    # Return the highest scoring URL
    best = scored_urls.max_by { |u| u[:score] }
    best[:score] > 0.3 ? best[:url] : nil
  end

  def extract_product_links(html, domain)
    urls = []

    # Extract all href attributes
    html.scan(/href=["']([^"']+)["']/i).flatten.each do |url|
      # Normalize URL
      normalized = normalize_url(url, domain)
      next unless normalized

      # Filter to likely product pages
      next unless looks_like_product_url?(normalized)

      urls << normalized
    end

    urls.uniq
  end

  def normalize_url(url, domain)
    return nil if url.blank?
    return nil if url.start_with?("#", "javascript:", "mailto:")

    # Handle relative URLs
    if url.start_with?("/")
      return "https://#{domain}#{url}"
    end

    # Handle protocol-relative
    if url.start_with?("//")
      return "https:#{url}"
    end

    # Only return URLs from the same domain
    return url if url.include?(domain.gsub("www.", ""))

    nil
  end

  def looks_like_product_url?(url)
    # Common product URL patterns
    patterns = [
      %r{/products?/}i,
      %r{/p/[a-z0-9\-]+}i,
      %r{/dp/[A-Z0-9]+}i,            # Amazon
      %r{/gp/product/}i,              # Amazon
      %r{/itm/}i,                     # eBay
      %r{/listing/\d+}i,              # Etsy
      %r{/prd/\d+}i,                  # ASOS
      %r{-p\d+}i,                     # Various
      %r{/[a-z0-9\-]+-\d+\.html}i,    # Various
      %r{/item/}i,
      # Locale-prefixed product URLs (common for international sites)
      %r{/en-[a-z]{2}/[a-z0-9\-]+$}i,
      %r{/[a-z]{2}-[a-z]{2}/[a-z0-9\-]+$}i,
      %r{/usd/[a-z0-9\-]+}i,
      %r{/gbp/[a-z0-9\-]+}i,
      %r{/eur/[a-z0-9\-]+}i,
      # Slug-based URLs ending in alphanumeric (common pattern)
      %r{/[a-z0-9]+(?:-[a-z0-9]+){2,}$}i,
      # Category/product patterns
      %r{/[a-z]+/[a-z0-9\-]+(?:-[a-z0-9]+)+$}i
    ]

    # Exclude common non-product patterns
    exclusions = [
      %r{/search}i,
      %r{/category}i,
      %r{/collection}i,
      %r{/blog}i,
      %r{/account}i,
      %r{/cart}i,
      %r{/checkout}i,
      %r{/contact}i,
      %r{/about}i,
      %r{/help}i,
      %r{/faq}i,
      %r{/terms}i,
      %r{/privacy}i,
      %r{\.(jpg|png|gif|css|js|svg)}i
    ]

    return false if exclusions.any? { |p| url.match?(p) }
    patterns.any? { |p| url.match?(p) }
  end

  def calculate_relevance_score(url, product_name)
    score = 0.0

    # Extract product name words
    name_words = product_name.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 3 }
    return 0.0 if name_words.empty?

    # URL slug typically contains product name
    url_slug = url.downcase.gsub(/[^a-z0-9]/, " ")

    # Score based on how many product name words appear in URL
    matches = name_words.count { |word| url_slug.include?(word) }
    score = matches.to_f / name_words.length

    # Bonus for exact phrase match
    clean_name = product_name.downcase.gsub(/[^a-z0-9]/, "")
    clean_url = url.downcase.gsub(/[^a-z0-9]/, "")
    score += 0.3 if clean_url.include?(clean_name)

    score
  end
end
