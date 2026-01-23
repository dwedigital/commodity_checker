class EmailParserService
  # Configuration constants
  MIN_PRODUCT_DESCRIPTION_LENGTH = 4
  MAX_PRODUCT_DESCRIPTION_LENGTH = 150
  MAX_LINE_LENGTH_FOR_PRODUCT = 80
  MAX_PRODUCT_DESCRIPTIONS = 10
  MAX_PRODUCT_IMAGES = 10
  MIN_IMAGE_DIMENSION = 50

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
      product_images: extract_product_images,
      delivery_info: extract_delivery_info
    }
  end

  def extract_delivery_info
    DeliveryDateExtractorService.new(
      email_body: @html.presence || @text,
      email_date: @inbound_email.created_at&.to_date || Date.current
    ).extract
  end

  def extract_product_urls
    extractor = ProductUrlExtractorService.new(@text)
    extractor.extract
  end

  def extract_tracking_urls
    urls = []

    extract_carrier_tracking_urls(urls)
    extract_generic_tracking_urls(urls)
    extract_tracking_links_from_html(urls)

    # Enrich "unknown" carriers by looking at surrounding text context
    enrich_unknown_carriers_from_context(urls)

    urls.uniq { |u| u[:url] }
  end

  def extract_carrier_tracking_urls(urls)
    TRACKING_PATTERNS.each do |carrier, patterns|
      patterns.each do |pattern|
        @text.scan(pattern).each do |match|
          url = match.is_a?(Array) ? match.first : match
          url = "https://#{url}" unless url.start_with?("http")
          urls << { carrier: carrier.to_s, url: clean_url(url) }
        end
      end
    end
  end

  def extract_generic_tracking_urls(urls)
    @text.scan(%r{https?://[^\s"'<>]+}).each do |url|
      next if urls.any? { |u| u[:url] == url }
      next unless url.match?(/track|delivery|shipment|parcel/i)

      urls << { carrier: "unknown", url: clean_url(url) }
    end
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
    return "dhl" if text.match?(/\bdhl\b/i)
    return "ups" if text.match?(/\bups\b/i)
    return "fedex" if text.match?(/fedex/i)
    return "dpd" if text.match?(/\bdpd\b/i)
    return "evri" if text.match?(/evri|hermes/i)
    return "usps" if text.match?(/\busps\b/i)
    return "yodel" if text.match?(/yodel/i)
    "unknown"
  end

  # Look at text surrounding tracking URLs to detect carrier when URL doesn't reveal it
  # This handles cases where tracking URLs are wrapped in click-tracking redirects
  def enrich_unknown_carriers_from_context(urls)
    urls.each do |tracking_info|
      next unless tracking_info[:carrier] == "unknown"

      # First, try to find carrier mentioned near the URL in the text
      carrier = detect_carrier_near_url(tracking_info[:url])

      # If not found near URL, look for carrier mentions in tracking-related sections
      carrier ||= detect_carrier_from_tracking_section

      tracking_info[:carrier] = carrier if carrier && carrier != "unknown"
    end
  end

  # Look for carrier name mentioned within ~300 chars before or after the URL
  def detect_carrier_near_url(url)
    # Find the URL position in text (might be partial match due to URL encoding)
    url_snippet = url[0, 50] # Use first 50 chars to find position
    position = @text.index(url_snippet)

    if position
      # Get surrounding context (300 chars before and after)
      start_pos = [ position - 300, 0 ].max
      end_pos = [ position + url.length + 300, @text.length ].min
      context = @text[start_pos...end_pos]

      carrier = detect_carrier_from_text(context)
      return carrier if carrier != "unknown"
    end

    # Also check HTML for context around links
    if @html.present?
      # Look for carrier names near anchor tags containing this URL
      url_escaped = Regexp.escape(url[0, 40])
      @html.scan(/(.{0,300})<a[^>]*href=["'][^"']*#{url_escaped}[^"']*["'][^>]*>(.{0,100})/i).each do |before, anchor_text|
        context = "#{before} #{anchor_text}"
        carrier = detect_carrier_from_text(context)
        return carrier if carrier != "unknown"
      end
    end

    nil
  end

  # Look for carrier mentions in sections that talk about tracking/shipping
  def detect_carrier_from_tracking_section
    # Look for patterns like "Shipped via UPS", "Carrier: DHL", "Delivered by FedEx"
    tracking_patterns = [
      /(?:shipped|shipping|delivered|carrier|via|by|with)\s*(?:via|by|:)?\s*(\w+(?:\s+\w+)?)/i,
      /(\w+(?:\s+\w+)?)\s+(?:tracking|shipment|delivery)/i,
      /track\s+(?:your\s+)?(?:order\s+)?(?:with\s+)?(\w+)/i
    ]

    tracking_patterns.each do |pattern|
      @text.scan(pattern).flatten.each do |match|
        carrier = detect_carrier_from_text(match)
        return carrier if carrier != "unknown"
      end
    end

    nil
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

    clean_and_deduplicate_descriptions(descriptions)
  end

  def clean_and_deduplicate_descriptions(descriptions)
    descriptions
      .map { |d| clean_product_description(d) }
      .compact
      .reject { |d| d.length < MIN_PRODUCT_DESCRIPTION_LENGTH || d.length > MAX_PRODUCT_DESCRIPTION_LENGTH }
      .uniq { |d| normalize_for_dedup(d) }
      .first(MAX_PRODUCT_DESCRIPTIONS)
  end

  def normalize_for_dedup(text)
    text.downcase.gsub(/[^a-z0-9]/, "")
  end

  def extract_products_before_attributes(descriptions)
    lines = @text.split(/\n/).map(&:strip).reject(&:empty?)
    seen = Set.new

    lines.each_with_index do |line, index|
      next if skip_line_for_product_extraction?(line)

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

    # Extract img tags with src and optional alt text
    # Pattern captures: full img tag, src URL, and alt text (if present)
    @html.scan(/<img[^>]*>/i).each do |img_tag|
      src_match = img_tag.match(/src=["']([^"']+)["']/i)
      next unless src_match

      src = src_match[1]
      next if src.blank?
      next unless src.start_with?("http")  # Only absolute URLs
      next if likely_non_product_image?(src)

      # Extract alt text
      alt_match = img_tag.match(/alt=["']([^"']*)["']/i)
      alt_text = alt_match ? alt_match[1].strip : nil

      # Skip if alt text indicates non-product image
      next if alt_text && likely_non_product_alt_text?(alt_text)

      # Check for size hints - very small images are likely icons
      width_match = img_tag.match(/width=["']?(\d+)/i)
      height_match = img_tag.match(/height=["']?(\d+)/i)

      width = width_match ? width_match[1].to_i : nil
      height = height_match ? height_match[1].to_i : nil

      # Skip very small images (likely icons/pixels)
      next if width && width < MIN_IMAGE_DIMENSION
      next if height && height < MIN_IMAGE_DIMENSION

      images << {
        url: src,
        alt_text: alt_text,
        width: width,
        height: height
      }
    end

    sort_and_limit_images(images)
  end

  def sort_and_limit_images(images)
    # Sort by size (larger images first, as they're more likely to be product images)
    images.sort_by { |img| -(img[:width] || 0) * (img[:height] || 0) }
          .uniq { |img| img[:url] }
          .first(MAX_PRODUCT_IMAGES)
  end

  # Match extracted images to product descriptions using alt text
  # Returns array of image URLs in the order matching the products
  def match_images_to_products(images, product_descriptions)
    return [] if images.blank? || product_descriptions.blank?

    matched_images = []

    product_descriptions.each do |product_desc|
      best_match = find_best_image_match(images, product_desc)
      matched_images << (best_match ? best_match[:url] : nil)
    end

    matched_images
  end

  private

  def find_best_image_match(images, product_desc)
    return nil if images.blank? || product_desc.blank?

    product_words = extract_keywords(product_desc)
    return nil if product_words.empty?

    best_match = nil
    best_score = 0

    images.each do |img|
      next if img[:alt_text].blank?

      alt_words = extract_keywords(img[:alt_text])
      next if alt_words.empty?

      # Calculate match score based on keyword overlap
      score = calculate_match_score(product_words, alt_words)

      if score > best_score
        best_score = score
        best_match = img
      end
    end

    # Only return match if score meets minimum threshold
    best_score >= 0.3 ? best_match : nil
  end

  def extract_keywords(text)
    return [] if text.blank?

    # Normalize and extract meaningful words
    text.downcase
        .gsub(/[^a-z0-9\s-]/, " ")
        .split(/\s+/)
        .reject { |w| w.length < 3 }
        .reject { |w| stop_words.include?(w) }
        .uniq
  end

  def stop_words
    %w[the and for with from color size qty quantity item product order your]
  end

  def calculate_match_score(product_words, alt_words)
    return 0 if product_words.empty? || alt_words.empty?

    # Count how many product words appear in alt text
    matches = (product_words & alt_words).length

    # Score is proportion of product words found in alt text
    matches.to_f / product_words.length
  end

  def likely_non_product_alt_text?(alt_text)
    return false if alt_text.blank?

    non_product_alt_patterns = [
      /^logo$/i,
      /\blogo\b/i,
      /^icon$/i,
      /^brand$/i,
      /^company/i,
      /facebook|twitter|instagram|pinterest|linkedin/i,
      /social/i,
      /payment|visa|mastercard|amex|paypal/i,
      /header|footer|banner/i,
      /spacer|pixel|tracking/i,
      /button|cta/i,
      /^$/  # Empty alt text
    ]

    non_product_alt_patterns.any? { |pattern| alt_text.match?(pattern) }
  end

  def likely_non_product_image?(url)
    NON_PRODUCT_IMAGE_PATTERNS.any? { |pattern| url.match?(pattern) }
  end

  def skip_line_for_product_extraction?(line)
    # Skip attribute or header lines
    return true if line.match?(/^(Color|Size|Qty|Quantity|Article|SKU|Item\s*#|Price|Total|Subtotal|Shipping|Discount|Order|Payment|Delivery|Thank|Info|Subscribe|Follow)[\s:]/i)
    # Skip price lines
    return true if line.match?(/^\d+[\s]*(USD|GBP|EUR|£|\$|x\s)/i)
    # Skip numeric-only lines
    return true if line.match?(/^[\d\s.,£$€]+$/)
    # Skip lines that are too short or too long
    return true if line.length < MIN_PRODUCT_DESCRIPTION_LENGTH || line.length > MAX_LINE_LENGTH_FOR_PRODUCT
    # Skip lines that are just bracketed text (often image alt text)
    return true if line.match?(/^\[.+\]$/)

    false
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
    return nil if desc.length < MIN_PRODUCT_DESCRIPTION_LENGTH
    return nil if desc.match?(/^[\d\s.,]+$/)
    return nil if non_product_pattern?(desc)

    desc.presence
  end

  def non_product_pattern?(text)
    text.match?(/^(Total|Subtotal|Shipping|Tax|Discount|Order|Thank|Subscribe|Follow|View|Copyright|Color|Size|Qty|Your order|Order details|Payment method|Delivery|Next step)/i)
  end

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
