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
    global_e: [
      %r{global-e\.com/[^\s"'<>]*track[^\s"'<>]*}i,
      %r{globale\.com/[^\s"'<>]*track[^\s"'<>]*}i,
      %r{web\.global-e\.com[^\s"'<>]*}i
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

  # Common patterns for non-product images to filter out
  NON_PRODUCT_IMAGE_PATTERNS = [
    /logo/i,
    /icon/i,
    /social/i,
    /facebook|twitter|instagram|pinterest|youtube|linkedin|tiktok/i,
    /tracking|pixel|beacon|spacer|blank|clear|1x1/i,
    /email[-_]?header|email[-_]?footer|banner/i,
    /button|cta|arrow|chevron/i,
    /payment|visa|mastercard|amex|paypal|apple[-_]?pay|google[-_]?pay/i,
    /rating|star|review/i,
    /avatar|profile/i,
    /\.gif$/i,  # Usually tracking pixels or animations
    /data:image/i  # Inline data URIs (usually icons)
  ].freeze

  attr_reader :inbound_email

  def initialize(inbound_email)
    @inbound_email = inbound_email
    @text = [ inbound_email.subject, inbound_email.body_text ].compact.join("\n")
    @html = inbound_email.body_html
  end

  def parse
    {
      tracking_urls: extract_tracking_urls,
      product_urls: extract_product_urls,
      order_reference: extract_order_reference,
      retailer_name: identify_retailer,
      product_descriptions: extract_product_descriptions,
      product_images: extract_product_images
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

    # Extract tracking links from HTML where text mentions "tracking" even if URL is a redirect
    extract_tracking_links_from_html(urls)

    urls.uniq { |u| u[:url] }
  end

  def extract_tracking_links_from_html(urls)
    return unless @html.present?

    # Pattern 1 (HIGHEST PRIORITY): Text like "tracking number: XXX" followed by a link
    # Common in plain-text-style HTML: "Global-e tracking number: LTN429578213<https://...>"
    # This pattern captures the tracking number so we can identify the carrier
    @text.scan(/(?:(\w+(?:-\w+)?)\s+)?tracking\s*(?:number|#|no\.?)?:?\s*([A-Z0-9]{8,20})\s*[<\[]?(https?:\/\/[^\s>\]]+)/i).each do |carrier_hint, tracking_num, url|
      next if url.blank? || urls.any? { |u| u[:url] == url }
      carrier = detect_carrier_from_text(carrier_hint) if carrier_hint.present?
      carrier ||= detect_carrier_from_tracking_number(tracking_num)
      urls << { carrier: carrier, url: clean_url(url), tracking_number: tracking_num }
    end

    # Pattern 2: Links where anchor text contains tracking number pattern
    # e.g., <a href="...">LTN429578213</a> or "tracking number: <a>XXX</a>"
    @html.scan(/<a[^>]+href=["']([^"']+)["'][^>]*>([^<]*(?:tracking|LTN|track)[^<]*)<\/a>/i).each do |url, text|
      next if url.blank? || urls.any? { |u| u[:url] == url }
      carrier = detect_carrier_from_text(text)
      urls << { carrier: carrier, url: clean_url(url) }
    end

    # Pattern 3: Look for links near tracking keywords in HTML (fallback)
    @html.scan(/tracking[^<]*<a[^>]+href=["']([^"']+)["']/i).each do |match|
      url = match.is_a?(Array) ? match.first : match
      next if url.blank? || urls.any? { |u| u[:url] == url }
      urls << { carrier: "unknown", url: clean_url(url) }
    end
  end

  def detect_carrier_from_text(text)
    return "global_e" if text.match?(/global-?e/i)
    return "royal_mail" if text.match?(/royal\s*mail/i)
    return "dhl" if text.match?(/dhl/i)
    return "ups" if text.match?(/ups/i)
    return "fedex" if text.match?(/fedex/i)
    return "dpd" if text.match?(/dpd/i)
    return "evri" if text.match?(/evri|hermes/i)
    "unknown"
  end

  def detect_carrier_from_tracking_number(tracking_num)
    # Global-e tracking numbers often start with LTN
    return "global_e" if tracking_num.match?(/^LTN/i)
    # Royal Mail tracking numbers often start with letters and are 13+ chars
    return "royal_mail" if tracking_num.match?(/^[A-Z]{2}\d{9}[A-Z]{2}$/i)
    "unknown"
  end

  def extract_order_reference
    ORDER_REFERENCE_PATTERNS.each do |pattern|
      match = @text.match(pattern)
      return match[1] if match
    end
    nil
  end

  def identify_retailer
    # First try to extract original sender from forwarded email
    original_from = extract_original_from_address
    if original_from
      from_retailer = identify_from_email(original_from)
      return from_retailer if from_retailer
    end

    # Then check actual from address (may be forwarder's email)
    from_retailer = identify_from_email(inbound_email.from_address)
    return from_retailer if from_retailer

    # Then check from email content
    RETAILER_PATTERNS.each do |name, pattern|
      return name if @text.match?(pattern)
    end

    # Try to extract from original forwarded domain first, then outer from
    if original_from
      retailer = extract_retailer_from_domain(original_from)
      return retailer if retailer
    end

    extract_retailer_from_domain(inbound_email.from_address)
  end

  def extract_original_from_address
    # Pattern 1: "---------- Forwarded message ----------\nFrom: email@domain.com"
    if match = @text.match(/[-]+\s*Forwarded message\s*[-]+\s*\n\s*From:\s*([^\n<]+<)?([^>\n\s]+@[^>\n\s]+)/i)
      return match[2]
    end

    # Pattern 2: "-------- Original Message --------\nFrom: email@domain.com"
    if match = @text.match(/[-]+\s*Original Message\s*[-]+\s*\n\s*From:\s*([^\n<]+<)?([^>\n\s]+@[^>\n\s]+)/i)
      return match[2]
    end

    # Pattern 3: "From: Name <email@domain.com>" at start of forwarded content
    if match = @text.match(/\n\s*From:\s*(?:[^<\n]+<)?([^>\n\s]+@[^>\n\s]+)/i)
      return match[1]
    end

    # Pattern 4: "From: email@domain.com\nDate:" or "From: email@domain.com\nSent:"
    if match = @text.match(/From:\s*(?:[^<\n]+<)?([^>\n\s]+@[^>\n\s]+)[^@\n]*\n\s*(?:Date|Sent|To):/i)
      return match[1]
    end

    nil
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
      # Skip lines that are just bracketed text (often image alt text)
      next if line.match?(/^\[.+\]$/)

      # Check if followed by product attributes
      next_lines = lines[index + 1, 6] || []
      next_chunk = next_lines.join(" ")
      if next_chunk.match?(/\b(Color|Size|Qty|Quantity|Article|SKU)[\s:]/i)
        # Build enhanced description with attributes
        product_name = line.gsub(/^\[|\]$/, "").strip  # Remove brackets if present
        enhanced = build_product_with_attributes(product_name, next_lines)

        normalized = enhanced.downcase.gsub(/\s+/, " ")
        next if seen.include?(normalized)
        seen.add(normalized)
        descriptions << enhanced
      end
    end
  end

  def build_product_with_attributes(name, attribute_lines)
    parts = [ name ]

    attribute_lines.each do |line|
      # Extract color
      if match = line.match(/^Color:\s*(.+)/i)
        parts << "Color: #{match[1]}"
      end
      # Extract material
      if match = line.match(/^Material:\s*(.+)/i)
        parts << "Material: #{match[1]}"
      end
      # Stop at price or quantity lines
      break if line.match?(/^\d+[\s]*(USD|GBP|EUR|£|\$)/i)
      break if line.match?(/^(Qty|Quantity):/i)
    end

    parts.join(" - ")
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

  def extract_product_images
    return [] if @html.blank?

    images = []

    # Extract all img src URLs from HTML
    @html.scan(/<img[^>]+src=["']([^"']+)["'][^>]*>/i).flatten.each do |src|
      next if src.blank?
      next unless src.start_with?("http")  # Only absolute URLs
      next if likely_non_product_image?(src)

      # Check for size hints - very small images are likely icons
      width_match = @html.match(/<img[^>]+src=["']#{Regexp.escape(src)}["'][^>]*width=["']?(\d+)/i)
      height_match = @html.match(/<img[^>]+src=["']#{Regexp.escape(src)}["'][^>]*height=["']?(\d+)/i)

      width = width_match ? width_match[1].to_i : nil
      height = height_match ? height_match[1].to_i : nil

      # Skip very small images (likely icons/pixels)
      next if width && width < 50
      next if height && height < 50

      images << {
        url: src,
        width: width,
        height: height
      }
    end

    # Sort by size (larger images first, as they're more likely to be product images)
    images.sort_by { |img| -(img[:width] || 0) * (img[:height] || 0) }
          .map { |img| img[:url] }
          .uniq
          .first(10)  # Limit to 10 images
  end

  def likely_non_product_image?(url)
    NON_PRODUCT_IMAGE_PATTERNS.any? { |pattern| url.match?(pattern) }
  end

  def clean_product_description(desc)
    return nil unless desc.is_a?(String)

    desc = desc.strip
               .gsub(/^[-•*]\s*/, "")              # Remove leading bullets
               .gsub(/^\[|\]$/, "")                # Remove brackets
               .gsub(/\s+/, " ")
               .gsub(/[\$£€][\d,.]+/, "")
               .gsub(/\d+\s*(USD|GBP|EUR)\b/i, "")
               .strip

    # Filter out non-products
    return nil if desc.length < 4
    return nil if desc.match?(/^[\d\s.,]+$/)
    return nil if desc.match?(/^(Total|Subtotal|Shipping|Tax|Discount|Order|Thank|Subscribe|Follow|View|Copyright|Color|Size|Qty|Your order|Order details|Payment method|Delivery|Next step)/i)

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
                 .sub(/^(mail|email|noreply|no-reply|shipping|orders?|info|news|newsletter|support|help)\./i, "")
                 .gsub(/[._-]/, " ")
                 .titleize

    name.length > 2 ? name : nil
  end
end
