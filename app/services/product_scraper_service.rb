class ProductScraperService
  RETAILER_PATTERNS = {
    "amazon" => /amazon\.(com|co\.uk|de|fr|es|it)/i,
    "ebay" => /ebay\.(com|co\.uk)/i,
    "asos" => /asos\.com/i,
    "zalando" => /zalando\./i,
    "john_lewis" => /johnlewis\.com/i,
    "argos" => /argos\.co\.uk/i,
    "currys" => /currys\.co\.uk/i,
    "very" => /very\.co\.uk/i,
    "next" => /next\.co\.uk/i,
    "marks_spencer" => /marksandspencer\.com/i,
    "boots" => /boots\.com/i,
    "superdrug" => /superdrug\.com/i,
    "aliexpress" => /aliexpress\.com/i,
    "etsy" => /etsy\.com/i,
    "wayfair" => /wayfair\.(com|co\.uk)/i,
    "lululemon" => /lululemon\.com/i,
    "prodirect" => /prodirectsport\.com/i
  }.freeze

  # Errors that should trigger ScrapingBee fallback
  FALLBACK_ERRORS = [
    "HTTP 403",
    "HTTP 401",
    "HTTP 503",
    "Request timed out",
    "Connection failed"
  ].freeze

  SCRAPINGBEE_API_URL = "https://app.scrapingbee.com/api/v1/".freeze

  def initialize
    @conn = Faraday.new do |f|
      f.options.timeout = 20
      f.options.open_timeout = 10
      f.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      f.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      f.headers["Accept-Language"] = "en-GB,en;q=0.9"
      f.response :follow_redirects, limit: 5
      f.adapter Faraday.default_adapter
    end

    @scrapingbee_conn = Faraday.new do |f|
      f.options.timeout = 60  # ScrapingBee can take longer
      f.options.open_timeout = 30
      f.adapter Faraday.default_adapter
    end
  end

  def scrape(url)
    return error_result("URL is blank") if url.blank?

    retailer = detect_retailer(url)

    # Try direct fetch first
    response = fetch_page(url)

    # If direct fetch failed with a recoverable error, try ScrapingBee
    if response[:error] && should_use_fallback?(response[:error])
      Rails.logger.info("ProductScraperService: Direct fetch failed (#{response[:error]}), trying ScrapingBee for #{url}")
      response = fetch_via_scrapingbee(url)
    end

    return error_result("Failed to fetch page: #{response[:error]}") if response[:error]

    html = response[:body]
    result = extract_product_data(html, url)
    result[:retailer_name] = retailer
    result[:url] = url
    result[:scraped_at] = Time.current
    result[:fetched_via] = response[:fetched_via] || :direct

    # Determine scrape status based on quality
    result[:status] = determine_status(result)
    result
  rescue => e
    Rails.logger.error("ProductScraperService error for #{url}: #{e.message}")
    error_result(e.message)
  end

  def detect_retailer(url)
    RETAILER_PATTERNS.each do |name, pattern|
      return name if url.match?(pattern)
    end
    extract_domain(url)
  end

  private

  def fetch_page(url)
    response = @conn.get(url)

    if response.success?
      { body: response.body, status: response.status, fetched_via: :direct }
    else
      { error: "HTTP #{response.status}" }
    end
  rescue Faraday::TimeoutError
    { error: "Request timed out" }
  rescue Faraday::ConnectionFailed => e
    { error: "Connection failed: #{e.message}" }
  rescue Faraday::Error => e
    { error: e.message }
  end

  def fetch_via_scrapingbee(url)
    api_key = ENV["SCRAPINGBEE_API_KEY"]

    unless api_key.present?
      Rails.logger.warn("ProductScraperService: SCRAPINGBEE_API_KEY not configured, cannot use fallback")
      return { error: "ScrapingBee not configured" }
    end

    params = {
      api_key: api_key,
      url: url,
      render_js: "true",           # Render JavaScript for SPAs
      premium_proxy: "true",       # Use premium proxies for better success rate
      country_code: "gb"           # UK proxy for UK-specific content
    }

    response = @scrapingbee_conn.get(SCRAPINGBEE_API_URL, params)

    if response.success?
      Rails.logger.info("ProductScraperService: ScrapingBee succeeded for #{url}")
      { body: response.body, status: response.status, fetched_via: :scrapingbee }
    else
      # ScrapingBee returns error details in the response body
      error_msg = "ScrapingBee HTTP #{response.status}"
      begin
        error_data = JSON.parse(response.body)
        error_msg = "ScrapingBee: #{error_data['message']}" if error_data["message"]
      rescue JSON::ParserError
        # Use default error message
      end
      Rails.logger.error("ProductScraperService: ScrapingBee failed for #{url}: #{error_msg}")
      { error: error_msg }
    end
  rescue Faraday::TimeoutError
    Rails.logger.error("ProductScraperService: ScrapingBee timed out for #{url}")
    { error: "ScrapingBee request timed out" }
  rescue Faraday::Error => e
    Rails.logger.error("ProductScraperService: ScrapingBee error for #{url}: #{e.message}")
    { error: "ScrapingBee error: #{e.message}" }
  end

  def should_use_fallback?(error)
    return false unless ENV["SCRAPINGBEE_API_KEY"].present?

    FALLBACK_ERRORS.any? { |fallback_error| error.to_s.include?(fallback_error) }
  end

  def extract_product_data(html, url)
    result = {}

    # Try extraction methods in priority order
    json_ld_data = extract_json_ld(html)
    og_data = extract_open_graph(html)
    meta_data = extract_meta_tags(html)
    html_data = extract_from_html(html)

    # Merge data, preferring structured sources
    result[:structured_data] = json_ld_data if json_ld_data.present?

    # Title: JSON-LD > OG > Meta > HTML
    result[:title] = clean_text(
      json_ld_data&.dig("name") ||
      og_data[:title] ||
      meta_data[:title] ||
      html_data[:title]
    )

    # Description: JSON-LD > OG > Meta > HTML
    result[:description] = clean_text(
      json_ld_data&.dig("description") ||
      og_data[:description] ||
      meta_data[:description] ||
      html_data[:description]
    )

    # Brand
    result[:brand] = clean_text(extract_brand(json_ld_data) || html_data[:brand])

    # Category
    result[:category] = clean_text(
      json_ld_data&.dig("category") ||
      extract_breadcrumb_category(html) ||
      html_data[:category]
    )

    # Price
    price_data = extract_price(json_ld_data, og_data, html)
    result[:price] = price_data[:price]
    result[:currency] = price_data[:currency]

    # Material (often in description or specific fields)
    result[:material] = clean_text(extract_material(json_ld_data, html))

    # Image - handle both string and array formats
    image = json_ld_data&.dig("image") || og_data[:image] || extract_product_image(html)
    image = image.first if image.is_a?(Array)
    image = image["url"] if image.is_a?(Hash) && image["url"]
    result[:image_url] = normalize_image_url(image, url) if image.present?

    result
  end

  def extract_json_ld(html)
    # Find all JSON-LD scripts
    scripts = html.scan(/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/im)

    scripts.each do |match|
      begin
        json_text = match[0].strip
        data = JSON.parse(json_text)

        # Handle @graph format
        if data.is_a?(Hash) && data["@graph"]
          product = data["@graph"].find { |item| item["@type"] == "Product" }
          return product if product
        end

        # Direct Product type
        if data.is_a?(Hash) && data["@type"] == "Product"
          return data
        end

        # Array of objects
        if data.is_a?(Array)
          product = data.find { |item| item.is_a?(Hash) && item["@type"] == "Product" }
          return product if product
        end
      rescue JSON::ParserError
        next
      end
    end

    nil
  end

  def extract_open_graph(html)
    {
      title: extract_meta_content(html, 'property="og:title"') ||
             extract_meta_content(html, "property='og:title'"),
      description: extract_meta_content(html, 'property="og:description"') ||
                   extract_meta_content(html, "property='og:description'"),
      image: extract_meta_content(html, 'property="og:image"') ||
             extract_meta_content(html, "property='og:image'"),
      price: extract_meta_content(html, 'property="og:price:amount"') ||
             extract_meta_content(html, 'property="product:price:amount"')
    }
  end

  def extract_meta_tags(html)
    {
      title: extract_meta_content(html, 'name="title"') ||
             html.match(/<title[^>]*>([^<]+)<\/title>/i)&.[](1)&.strip,
      description: extract_meta_content(html, 'name="description"')
    }
  end

  def extract_meta_content(html, attr)
    pattern = /<meta[^>]*#{Regexp.escape(attr)}[^>]*content=["']([^"']+)["'][^>]*>/i
    match = html.match(pattern)
    return match[1].strip if match

    # Try reverse order (content before property)
    pattern2 = /<meta[^>]*content=["']([^"']+)["'][^>]*#{Regexp.escape(attr)}[^>]*>/i
    match2 = html.match(pattern2)
    match2&.[](1)&.strip
  end

  def extract_from_html(html)
    result = {}

    # Title from H1 or product-specific classes
    title_patterns = [
      /<h1[^>]*class="[^"]*product[^"]*"[^>]*>([^<]+)</i,
      /<h1[^>]*id="[^"]*product[^"]*"[^>]*>([^<]+)</i,
      /<h1[^>]*>([^<]+)</i,
      /<span[^>]*class="[^"]*product-title[^"]*"[^>]*>([^<]+)</i,
      /<div[^>]*class="[^"]*product-name[^"]*"[^>]*>([^<]+)</i
    ]

    title_patterns.each do |pattern|
      match = html.match(pattern)
      if match
        result[:title] = clean_text(match[1])
        break
      end
    end

    # Description from product-specific elements
    desc_patterns = [
      /<div[^>]*class="[^"]*product-description[^"]*"[^>]*>(.*?)<\/div>/im,
      /<div[^>]*id="[^"]*description[^"]*"[^>]*>(.*?)<\/div>/im,
      /<p[^>]*class="[^"]*description[^"]*"[^>]*>([^<]+)</i
    ]

    desc_patterns.each do |pattern|
      match = html.match(pattern)
      if match
        result[:description] = clean_html(match[1])
        break
      end
    end

    # Brand
    brand_patterns = [
      /<span[^>]*class="[^"]*brand[^"]*"[^>]*>([^<]+)</i,
      /<a[^>]*class="[^"]*brand[^"]*"[^>]*>([^<]+)</i,
      /brand[:\s]*<[^>]*>([^<]+)</i
    ]

    brand_patterns.each do |pattern|
      match = html.match(pattern)
      if match
        result[:brand] = clean_text(match[1])
        break
      end
    end

    # Category from breadcrumbs or nav
    result[:category] = extract_breadcrumb_category(html)

    result
  end

  def extract_brand(json_ld)
    return nil unless json_ld

    brand = json_ld["brand"]
    return brand if brand.is_a?(String)
    return brand["name"] if brand.is_a?(Hash) && brand["name"]

    nil
  end

  def extract_price(json_ld, og_data, html)
    price = nil
    currency = nil

    # From JSON-LD offers
    if json_ld && json_ld["offers"]
      offers = json_ld["offers"]
      offers = offers.first if offers.is_a?(Array)

      if offers.is_a?(Hash)
        price = offers["price"]
        currency = offers["priceCurrency"]
      end
    end

    # From Open Graph
    price ||= og_data[:price]

    # From HTML patterns
    unless price
      price_patterns = [
        /(?:£|GBP)\s*([\d,]+\.?\d*)/,
        /(?:\$|USD)\s*([\d,]+\.?\d*)/,
        /(?:€|EUR)\s*([\d,]+\.?\d*)/,
        /price[:\s]*(?:£|\$|€)?\s*([\d,]+\.?\d*)/i
      ]

      price_patterns.each do |pattern|
        match = html.match(pattern)
        if match
          price = match[1].gsub(",", "")
          currency ||= detect_currency_from_html(html)
          break
        end
      end
    end

    { price: price, currency: currency }
  end

  def detect_currency_from_html(html)
    return "GBP" if html.include?("£") || html.match?(/\.co\.uk/i)
    return "USD" if html.include?("$") || html.match?(/\.com(?![^.]*\.uk)/i)
    return "EUR" if html.include?("€")

    nil
  end

  def extract_material(json_ld, html)
    # From JSON-LD
    if json_ld
      material = json_ld["material"]
      return material if material.is_a?(String)
    end

    # From HTML - look for material/composition sections
    material_patterns = [
      /material[:\s]*([^<\n]+)/i,
      /composition[:\s]*([^<\n]+)/i,
      /fabric[:\s]*([^<\n]+)/i,
      /made\s+(?:from|of)[:\s]*([^<\n]+)/i
    ]

    material_patterns.each do |pattern|
      match = html.match(pattern)
      if match
        material = clean_text(match[1])
        return material if material.length > 3 && material.length < 200
      end
    end

    nil
  end

  def extract_breadcrumb_category(html)
    # Look for breadcrumb navigation
    breadcrumb_patterns = [
      /<nav[^>]*class="[^"]*breadcrumb[^"]*"[^>]*>(.*?)<\/nav>/im,
      /<ol[^>]*class="[^"]*breadcrumb[^"]*"[^>]*>(.*?)<\/ol>/im,
      /<ul[^>]*class="[^"]*breadcrumb[^"]*"[^>]*>(.*?)<\/ul>/im
    ]

    breadcrumb_patterns.each do |pattern|
      match = html.match(pattern)
      if match
        breadcrumb_html = match[1]
        # Extract text from links
        items = breadcrumb_html.scan(/<a[^>]*>([^<]+)<\/a>/i).flatten
        items = items.reject { |item| item.strip.downcase == "home" }
        return items.join(" > ") if items.any?
      end
    end

    nil
  end

  def extract_product_image(html)
    patterns = [
      /<img[^>]*class="[^"]*product[^"]*"[^>]*src=["']([^"']+)["']/i,
      /<img[^>]*id="[^"]*product[^"]*"[^>]*src=["']([^"']+)["']/i,
      /<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i
    ]

    patterns.each do |pattern|
      match = html.match(pattern)
      return match[1] if match
    end

    nil
  end

  def normalize_image_url(image_url, page_url)
    return nil if image_url.blank?

    # Handle protocol-relative URLs
    if image_url.start_with?("//")
      return "https:#{image_url}"
    end

    # Handle relative URLs
    unless image_url.start_with?("http")
      uri = URI.parse(page_url)
      base = "#{uri.scheme}://#{uri.host}"
      return image_url.start_with?("/") ? "#{base}#{image_url}" : "#{base}/#{image_url}"
    end

    image_url
  rescue URI::InvalidURIError
    image_url
  end

  def extract_domain(url)
    uri = URI.parse(url)
    uri.host&.gsub(/^www\./, "")&.split(".")&.first
  rescue URI::InvalidURIError
    nil
  end

  def clean_text(text)
    return nil if text.blank?

    # Decode HTML entities and normalize whitespace
    text = CGI.unescapeHTML(text.to_s)
    text.strip.gsub(/\s+/, " ")
  end

  def clean_html(html)
    return nil if html.blank?

    # Remove tags
    text = html.gsub(/<[^>]+>/, " ")
    # Decode entities
    text = CGI.unescapeHTML(text)
    # Normalize whitespace
    text.strip.gsub(/\s+/, " ")
  end

  def determine_status(result)
    if result[:title].present? && result[:description].present?
      :completed
    elsif result[:title].present? || result[:description].present?
      :partial
    else
      :failed
    end
  end

  def error_result(message)
    {
      status: :failed,
      error: message,
      scraped_at: Time.current
    }
  end
end
