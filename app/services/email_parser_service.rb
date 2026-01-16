class EmailParserService
  # Common tracking URL patterns for major carriers
  TRACKING_PATTERNS = {
    royal_mail: [
      %r{royalmail\.com/track[^\s"'<>]*}i,
      %r{parcelforce\.com/track[^\s"'<>]*}i
    ],
    dhl: [
      %r{dhl\.(com|co\.uk)/[^\s"'<>]*track[^\s"'<>]*}i,
      %r{webtrack\.dhlglobalmail\.com[^\s"'<>]*}i
    ],
    ups: [
      %r{ups\.com/track[^\s"'<>]*}i,
      %r{ups\.com/WebTracking[^\s"'<>]*}i
    ],
    fedex: [
      %r{fedex\.com/[^\s"'<>]*track[^\s"'<>]*}i
    ],
    usps: [
      %r{usps\.com/[^\s"'<>]*track[^\s"'<>]*}i,
      %r{tools\.usps\.com/go/TrackConfirmAction[^\s"'<>]*}i
    ],
    amazon: [
      %r{https?://[^\s"'<>]*amazon\.(com|co\.uk|de|fr)[^\s"'<>]*progress-tracker[^\s"'<>]*}i,
      %r{https?://[^\s"'<>]*amazon\.(com|co\.uk|de|fr)[^\s"'<>]*/gp/css/shiptrack[^\s"'<>]*}i,
      %r{https?://track\.amazon\.(com|co\.uk)[^\s"'<>]*}i
    ],
    dpd: [
      %r{dpd\.(co\.uk|com)/track[^\s"'<>]*}i,
      %r{track\.dpd\.(co\.uk|com)[^\s"'<>]*}i
    ],
    hermes: [
      %r{myhermes\.co\.uk/track[^\s"'<>]*}i,
      %r{evri\.com/track[^\s"'<>]*}i
    ],
    yodel: [
      %r{yodel\.co\.uk/track[^\s"'<>]*}i
    ],
    generic: [
      %r{https?://[^\s"'<>]*track[^\s"'<>]*order[^\s"'<>]*}i,
      %r{https?://[^\s"'<>]*order[^\s"'<>]*track[^\s"'<>]*}i
    ]
  }.freeze

  # Patterns to extract order references
  ORDER_REFERENCE_PATTERNS = [
    /order\s*(?:#|number|no\.?|ref\.?)?:?\s*([A-Z0-9][\w-]{5,30})/i,
    /reference\s*(?:#|number|no\.?)?:?\s*([A-Z0-9][\w-]{5,30})/i,
    /tracking\s*(?:#|number|no\.?)?:?\s*([A-Z0-9][\w-]{8,30})/i,
    /shipment\s*(?:#|number|no\.?)?:?\s*([A-Z0-9][\w-]{5,30})/i
  ].freeze

  # Patterns to identify retailer from email
  RETAILER_PATTERNS = {
    "Amazon" => /amazon\.(com|co\.uk|de|fr|es|it)/i,
    "eBay" => /ebay\.(com|co\.uk)/i,
    "AliExpress" => /aliexpress\.com/i,
    "ASOS" => /asos\.com/i,
    "Zara" => /zara\.com/i,
    "H&M" => /hm\.com/i,
    "Apple" => /apple\.com/i,
    "John Lewis" => /johnlewis\.com/i,
    "Argos" => /argos\.co\.uk/i,
    "Currys" => /currys\.co\.uk/i,
    "Very" => /very\.co\.uk/i
  }.freeze

  attr_reader :inbound_email

  def initialize(inbound_email)
    @inbound_email = inbound_email
    @text = [inbound_email.subject, inbound_email.body_text].compact.join("\n")
  end

  def parse
    {
      tracking_urls: extract_tracking_urls,
      product_urls: extract_product_urls,
      order_reference: extract_order_reference,
      retailer_name: identify_retailer,
      product_descriptions: extract_product_descriptions
    }
  end

  def extract_product_urls
    extractor = ProductUrlExtractorService.new(@text)
    extractor.extract
  end

  def extract_tracking_urls
    urls = []

    TRACKING_PATTERNS.each do |carrier, patterns|
      patterns.each do |pattern|
        matches = @text.scan(pattern)
        matches.each do |match|
          url = match.is_a?(Array) ? match.first : match
          url = "https://#{url}" unless url.start_with?("http")
          urls << { carrier: carrier.to_s, url: clean_url(url) }
        end
      end
    end

    # Also extract any URLs that look like tracking links
    generic_urls = @text.scan(%r{https?://[^\s"'<>]+})
    generic_urls.each do |url|
      next if urls.any? { |u| u[:url] == url }
      next unless url.match?(/track|delivery|shipment|parcel/i)

      urls << { carrier: "unknown", url: clean_url(url) }
    end

    urls.uniq { |u| u[:url] }
  end

  def extract_order_reference
    ORDER_REFERENCE_PATTERNS.each do |pattern|
      match = @text.match(pattern)
      return match[1] if match
    end
    nil
  end

  def identify_retailer
    # First check from email address
    from_retailer = identify_from_email(inbound_email.from_address)
    return from_retailer if from_retailer

    # Then check from email content
    RETAILER_PATTERNS.each do |name, pattern|
      return name if @text.match?(pattern)
    end

    # Try to extract from email domain
    extract_retailer_from_domain(inbound_email.from_address)
  end

  def extract_product_descriptions
    descriptions = []

    # Strategy 1: Lines before product attributes (Color/Size/Qty/SKU)
    extract_products_before_attributes(descriptions)

    # Strategy 2: Explicit product patterns
    extract_explicit_product_patterns(descriptions)

    # Strategy 3: Quantity patterns (2x Widget, Qty: 1 Widget)
    extract_quantity_patterns(descriptions)

    # Clean up and deduplicate
    descriptions = descriptions
      .map { |d| clean_product_description(d) }
      .compact
      .reject { |d| d.length < 4 || d.length > 150 }
      .uniq { |d| d.downcase.gsub(/[^a-z0-9]/, "") }
      .first(10)

    descriptions
  end

  def extract_products_before_attributes(descriptions)
    lines = @text.split(/\n/).map(&:strip).reject(&:empty?)
    seen = Set.new

    lines.each_with_index do |line, index|
      # Skip if this line IS an attribute or header
      next if line.match?(/^(Color|Size|Qty|Quantity|Article|SKU|Item\s*#|Price|Total|Subtotal|Shipping|Discount|Order|Payment|Delivery|Thank|Info|Subscribe|Follow)[\s:]/i)
      next if line.match?(/^\d+[\s]*(USD|GBP|EUR|£|\$|x\s)/i)
      next if line.match?(/^[\d\s.,£$€]+$/)
      next if line.length < 4 || line.length > 80

      # Check if followed by product attributes
      next_chunk = lines[index + 1, 4]&.join(" ") || ""
      if next_chunk.match?(/\b(Color|Size|Qty|Quantity|Article|SKU)[\s:]/i)
        normalized = line.downcase.gsub(/\s+/, " ")
        next if seen.include?(normalized)
        seen.add(normalized)
        descriptions << line
      end
    end
  end

  def extract_explicit_product_patterns(descriptions)
    # List items with bullets or dashes
    @text.scan(/^[\s]*[-•*]\s*(.+?)$/m).flatten.each { |d| descriptions << d }

    # "Items: x, y, z" or "Products: x, y"
    @text.scan(/(?:items?|products?|contains?):\s*(.+?)(?:\n\n|\z)/im).flatten.each do |list|
      list.split(/[,\n]/).each { |d| descriptions << d.strip }
    end
  end

  def extract_quantity_patterns(descriptions)
    # "2x Product Name" or "2 x Product Name" - stop at newline
    @text.scan(/^\s*\d+\s*[x×]\s+(.+?)$/i).flatten.each do |d|
      descriptions << d.strip
    end
  end

  def clean_product_description(desc)
    return nil unless desc.is_a?(String)

    desc = desc.strip
               .gsub(/^[-•*]\s*/, "")              # Remove leading bullets
               .gsub(/\s+/, " ")
               .gsub(/[\$£€][\d,.]+/, "")
               .gsub(/\d+\s*(USD|GBP|EUR)\b/i, "")
               .strip

    # Filter out non-products
    return nil if desc.length < 4
    return nil if desc.match?(/^[\d\s.,]+$/)
    return nil if desc.match?(/^(Total|Subtotal|Shipping|Tax|Discount|Order|Thank|Subscribe|Follow|View|Copyright|Color|Size|Qty)/i)

    desc.presence
  end

  private

  def clean_url(url)
    # Remove trailing punctuation and clean up
    url.gsub(/[.,;:!?\])\}>]+$/, "")
       .gsub(/&amp;/, "&")
  end

  def identify_from_email(email_address)
    return nil unless email_address

    RETAILER_PATTERNS.each do |name, pattern|
      return name if email_address.match?(pattern)
    end
    nil
  end

  def extract_retailer_from_domain(email_address)
    return nil unless email_address

    # Extract domain and try to make a readable name
    match = email_address.match(/@([^@]+)$/)
    return nil unless match

    domain = match[1]
    # Remove common suffixes and clean up
    name = domain.sub(/\.(com|co\.uk|net|org|io).*$/i, "")
                 .sub(/^(mail|email|noreply|no-reply|shipping|orders?)\./i, "")
                 .gsub(/[._-]/, " ")
                 .titleize

    name.length > 2 ? name : nil
  end
end
