class ProductUrlExtractorService
  # Patterns for product page URLs (not tracking or other pages)
  PRODUCT_URL_PATTERNS = {
    amazon: [
      # Amazon product pages: /dp/ASIN or /gp/product/ASIN
      %r{https?://(?:www\.)?amazon\.(?:com|co\.uk|de|fr|es|it|ca|com\.au)/(?:[^\s"'<>]*/)?dp/([A-Z0-9]{10})[^\s"'<>]*}i,
      %r{https?://(?:www\.)?amazon\.(?:com|co\.uk|de|fr|es|it|ca|com\.au)/(?:[^\s"'<>]*/)?gp/product/([A-Z0-9]{10})[^\s"'<>]*}i
    ],
    ebay: [
      # eBay item pages
      %r{https?://(?:www\.)?ebay\.(?:com|co\.uk|de|fr)/itm/[^\s"'<>]*?(\d{10,14})[^\s"'<>]*}i
    ],
    asos: [
      %r{https?://(?:www\.)?asos\.com/[^\s"'<>]*/prd/(\d+)[^\s"'<>]*}i
    ],
    john_lewis: [
      %r{https?://(?:www\.)?johnlewis\.com/[^\s"'<>]*/p(\d+)[^\s"'<>]*}i
    ],
    argos: [
      %r{https?://(?:www\.)?argos\.co\.uk/product/(\d+)[^\s"'<>]*}i
    ],
    currys: [
      %r{https?://(?:www\.)?currys\.co\.uk/[^\s"'<>]*-(\d+)\.html[^\s"'<>]*}i
    ],
    very: [
      %r{https?://(?:www\.)?very\.co\.uk/[^\s"'<>]*/(\d+)\.d[^\s"'<>]*}i
    ],
    next: [
      %r{https?://(?:www\.)?next\.co\.uk/[^\s"'<>]*/([a-z0-9\-]+)[^\s"'<>]*}i
    ],
    etsy: [
      %r{https?://(?:www\.)?etsy\.com/[^\s"'<>]*/listing/(\d+)[^\s"'<>]*}i
    ],
    aliexpress: [
      %r{https?://(?:www\.)?aliexpress\.com/item/[^\s"'<>]*?(\d+)\.html[^\s"'<>]*}i
    ],
    wayfair: [
      %r{https?://(?:www\.)?wayfair\.(?:com|co\.uk)/[^\s"'<>]*\.html[^\s"'<>]*}i
    ]
  }.freeze

  # URLs to exclude (common in emails but not product pages)
  EXCLUDE_PATTERNS = [
    /unsubscribe/i,
    /privacy/i,
    /terms/i,
    /help/i,
    /contact/i,
    /support/i,
    /account/i,
    /login/i,
    /signin/i,
    /cart/i,
    /checkout/i,
    /order-?(?:status|history|tracking)/i,
    /mailto:/i,
    /tracking/i,
    /shipment/i,
    /delivery/i,
    /#/,  # Anchors
    /\.(?:jpg|jpeg|png|gif|svg|css|js)(?:\?|$)/i  # Static assets
  ].freeze

  def initialize(text)
    @text = text.to_s
  end

  def extract
    urls = []

    # First, try retailer-specific patterns
    PRODUCT_URL_PATTERNS.each do |retailer, patterns|
      patterns.each do |pattern|
        @text.scan(pattern) do
          full_match = $~[0]
          next if should_exclude?(full_match)

          urls << {
            url: clean_url(full_match),
            retailer: retailer.to_s,
            product_id: $~[1]
          }
        end
      end
    end

    # Then, try generic product URL patterns for other retailers
    generic_urls = extract_generic_product_urls
    urls.concat(generic_urls)

    # Deduplicate by URL
    urls.uniq { |u| u[:url] }
  end

  private

  def extract_generic_product_urls
    urls = []

    # Generic patterns that often indicate product pages
    generic_patterns = [
      # /product/ or /products/ paths
      %r{https?://[^\s"'<>]+/products?/[^\s"'<>]*}i,
      # /item/ paths
      %r{https?://[^\s"'<>]+/item/[^\s"'<>]*}i,
      # /p/ followed by ID (common pattern)
      %r{https?://[^\s"'<>]+/p/[a-z0-9\-]+[^\s"'<>]*}i
    ]

    generic_patterns.each do |pattern|
      @text.scan(pattern) do
        url = $~[0]
        next if should_exclude?(url)
        next if known_retailer_url?(url)  # Already captured by specific patterns

        retailer = detect_retailer(url)
        urls << {
          url: clean_url(url),
          retailer: retailer,
          product_id: nil
        }
      end
    end

    urls
  end

  def should_exclude?(url)
    EXCLUDE_PATTERNS.any? { |pattern| url.match?(pattern) }
  end

  def known_retailer_url?(url)
    PRODUCT_URL_PATTERNS.keys.any? do |retailer|
      url.match?(/#{retailer}/i)
    end
  end

  def detect_retailer(url)
    domain = extract_domain(url)
    return domain if domain

    "unknown"
  end

  def extract_domain(url)
    uri = URI.parse(url)
    host = uri.host&.gsub(/^www\./, "")

    # Get primary domain name
    parts = host&.split(".")
    return nil unless parts && parts.length >= 2

    # Handle co.uk style domains
    if parts[-2] == "co" && parts[-1] == "uk"
      parts[-3]
    else
      parts[-2]
    end
  rescue URI::InvalidURIError
    nil
  end

  def clean_url(url)
    # Remove trailing punctuation that might have been captured
    url = url.gsub(/[.,;:!?\])}>"']+$/, "")

    # Ensure URL starts with https if possible
    url = url.sub(/^http:/, "https:")

    # Remove common tracking parameters (keep the URL clean)
    uri = URI.parse(url)
    if uri.query
      params = URI.decode_www_form(uri.query)
      # Keep only non-tracking params
      clean_params = params.reject do |key, _|
        key.match?(/^(utm_|ref|tag|source|campaign|affiliate|tracking)/i)
      end
      uri.query = clean_params.any? ? URI.encode_www_form(clean_params) : nil
    end

    uri.to_s
  rescue URI::InvalidURIError
    url
  end
end
