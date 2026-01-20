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

  # Known retailers that always require ScrapingBee (skip direct fetch to save time)
  # Additional retailers are learned dynamically and cached
  KNOWN_SCRAPINGBEE_RETAILERS = %w[
    amazon john_lewis argos currys marks_spencer boots wayfair lululemon
  ].freeze

  # Cache key prefix for learned retailers
  RETAILER_CACHE_PREFIX = "scrapingbee_required:".freeze
  RETAILER_CACHE_EXPIRY = 30.days

  # Errors that should trigger ScrapingBee fallback
  FALLBACK_ERRORS = [
    "HTTP 403",
    "HTTP 401",
    "HTTP 503",
    "Request timed out",
    "Connection failed"
  ].freeze

  # Errors from premium proxy that should trigger stealth proxy fallback
  STEALTH_FALLBACK_ERRORS = [
    "ScrapingBee HTTP 500",
    "ScrapingBee HTTP 403",
    "ScrapingBee HTTP 401"
  ].freeze

  # Tracking parameters to strip from URLs before scraping
  TRACKING_PARAMS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content
    gclid gbraid gad_source gad_campaignid
    fbclid fb_action_ids fb_action_types fb_source
    mc_cid mc_eid
    ref ref_src ref_url
    _ga _gl
  ].freeze

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

    @scrapingbee = ScrapingbeeClient.new
  end

  def scrape(url)
    return error_result("URL is blank") if url.blank?

    # Clean URL by removing tracking parameters
    clean_url = strip_tracking_params(url)
    retailer = detect_retailer(clean_url)

    # Track fetch attempts for user feedback
    fetch_attempts = []
    direct_fetch_failed = false

    # Skip direct fetch for retailers that already require ScrapingBee
    if requires_scrapingbee?(retailer)
      Rails.logger.info("ProductScraperService: #{retailer} requires ScrapingBee, skipping direct fetch")
      response = { error: "Retailer requires proxy" }
    else
      # Try direct fetch first
      fetch_attempts << { method: "direct", status: "attempting", message: "Fetching page..." }
      response = fetch_page(clean_url)
      direct_fetch_failed = response[:error].present?
    end

    # If direct fetch failed with a recoverable error, try ScrapingBee with premium proxy
    if response[:error] && (requires_scrapingbee?(retailer) || should_use_fallback?(response[:error]))
      if fetch_attempts.any?
        fetch_attempts.last[:status] = "failed"
        fetch_attempts.last[:message] = "Direct fetch blocked (#{response[:error]})"
      end

      fetch_attempts << { method: "premium_proxy", status: "attempting", message: "Trying with proxy..." }
      Rails.logger.info("ProductScraperService: Direct fetch failed (#{response[:error]}), trying ScrapingBee premium proxy")
      response = fetch_via_scrapingbee(clean_url, stealth: false)

      # If ScrapingBee succeeded and direct fetch had failed, learn this retailer for future
      if response[:error].nil? && direct_fetch_failed
        remember_retailer_requires_scrapingbee(retailer)
      end

      # If premium proxy failed, try stealth proxy as last resort
      if response[:error] && should_use_stealth_fallback?(response[:error])
        fetch_attempts.last[:status] = "failed"
        fetch_attempts.last[:message] = "Premium proxy blocked (#{response[:error]})"

        fetch_attempts << { method: "stealth_proxy", status: "attempting", message: "Site has strong protection, using stealth mode..." }
        Rails.logger.info("ProductScraperService: Premium proxy failed (#{response[:error]}), trying ScrapingBee stealth proxy")
        response = fetch_via_scrapingbee(clean_url, stealth: true)
      end
    end

    if response[:error]
      fetch_attempts.last[:status] = "failed"
      fetch_attempts.last[:message] = response[:error]
      result = error_result("Failed to fetch page: #{response[:error]}")
      result[:fetch_attempts] = fetch_attempts
      return result
    end

    fetch_attempts.last[:status] = "success"
    fetch_attempts.last[:message] = "Page fetched successfully"

    html = response[:body]
    result = extract_product_data(html, url)
    result[:retailer_name] = retailer
    result[:url] = url
    result[:scraped_at] = Time.current
    result[:fetched_via] = response[:fetched_via] || :direct
    result[:fetch_attempts] = fetch_attempts

    # Determine scrape status based on quality
    result[:status] = determine_status(result)
    result
  rescue => e
    Rails.logger.error("ProductScraperService error for #{url}: #{e.message}")
    result = error_result(e.message)
    result[:fetch_attempts] = fetch_attempts if defined?(fetch_attempts)
    result
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

  def fetch_via_scrapingbee(url, stealth: false)
    country = detect_country_from_url(url)
    @scrapingbee.fetch(url, stealth: stealth, country_code: country)
  end

  def should_use_fallback?(error)
    return false unless ScrapingbeeClient.configured?

    FALLBACK_ERRORS.any? { |fallback_error| error.to_s.include?(fallback_error) }
  end

  def requires_scrapingbee?(retailer)
    return false unless ScrapingbeeClient.configured?

    retailer_key = retailer.to_s.downcase

    # Check hardcoded list first
    return true if KNOWN_SCRAPINGBEE_RETAILERS.include?(retailer_key)

    # Check if we've learned this retailer requires ScrapingBee
    Rails.cache.exist?("#{RETAILER_CACHE_PREFIX}#{retailer_key}")
  end

  def remember_retailer_requires_scrapingbee(retailer)
    retailer_key = retailer.to_s.downcase
    Rails.cache.write(
      "#{RETAILER_CACHE_PREFIX}#{retailer_key}",
      true,
      expires_in: RETAILER_CACHE_EXPIRY
    )
    Rails.logger.info("ProductScraperService: Learned that #{retailer} requires ScrapingBee (cached for 30 days)")
  end

  def should_use_stealth_fallback?(error)
    return false unless ScrapingbeeClient.configured?

    STEALTH_FALLBACK_ERRORS.any? { |fallback_error| error.to_s.include?(fallback_error) }
  end

  def strip_tracking_params(url)
    uri = URI.parse(url)
    return url unless uri.query

    params = URI.decode_www_form(uri.query)
    clean_params = params.reject { |key, _| TRACKING_PARAMS.include?(key) }

    if clean_params.empty?
      uri.query = nil
    else
      uri.query = URI.encode_www_form(clean_params)
    end

    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  def detect_country_from_url(url)
    # Extract country from URL patterns like .co.uk, /ie/, /de/, etc.
    return "gb" if url.match?(/\.co\.uk|\/uk\/|\/en-gb/i)
    return "ie" if url.match?(/\/ie\/|\/en-ie/i)
    return "de" if url.match?(/\.de\/|\/de\/|\/de-de/i)
    return "fr" if url.match?(/\.fr\/|\/fr\/|\/fr-fr/i)
    return "es" if url.match?(/\.es\/|\/es\/|\/es-es/i)
    return "it" if url.match?(/\.it\/|\/it\/|\/it-it/i)
    return "us" if url.match?(/\.com(?!\.)|\/us\/|\/en-us/i)

    "gb"  # Default to UK
  end

  def extract_product_data(html, url)
    # Try extraction methods in priority order
    sources = {
      json_ld: extract_json_ld(html),
      og: extract_open_graph(html),
      meta: extract_meta_tags(html),
      html: extract_from_html(html)
    }

    result = {}
    result[:structured_data] = sources[:json_ld] if sources[:json_ld].present?

    # Merge data, preferring structured sources (JSON-LD > OG > Meta > HTML)
    result[:title] = clean_text(first_available(
      sources[:json_ld]&.dig("name"),
      sources[:og][:title],
      sources[:meta][:title],
      sources[:html][:title]
    ))

    result[:description] = clean_text(first_available(
      sources[:json_ld]&.dig("description"),
      sources[:og][:description],
      sources[:meta][:description],
      sources[:html][:description]
    ))

    result[:brand] = clean_text(first_available(
      extract_brand(sources[:json_ld]),
      sources[:html][:brand]
    ))

    result[:category] = clean_text(first_available(
      sources[:json_ld]&.dig("category"),
      extract_breadcrumb_category(html),
      sources[:html][:category]
    ))

    price_data = extract_price(sources[:json_ld], sources[:og], html)
    result[:price] = price_data[:price]
    result[:currency] = price_data[:currency]

    result[:material] = clean_text(extract_material(sources[:json_ld], html))

    result[:image_url] = extract_and_normalize_image(sources, html, url)

    result
  end

  def first_available(*values)
    values.find(&:present?)
  end

  def extract_and_normalize_image(sources, html, url)
    image = first_available(
      sources[:json_ld]&.dig("image"),
      sources[:og][:image],
      extract_product_image(html)
    )

    # Handle array and hash formats
    image = image.first if image.is_a?(Array)
    image = image["url"] if image.is_a?(Hash) && image["url"]

    normalize_image_url(image, url) if image.present?
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
