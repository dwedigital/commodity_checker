class OrderMatcherService
  attr_reader :user, :parsed_data

  def initialize(user, parsed_data)
    @user = user
    @parsed_data = parsed_data
  end

  # Find an existing order that matches this email, or return nil
  def find_matching_order
    # Try matching strategies in order of confidence
    match_by_order_reference ||
      match_by_tracking_url ||
      match_by_retailer_and_timeframe
  end

  private

  # Most reliable: match by order reference number
  # Uses normalized comparison (case-insensitive, stripped of common prefixes)
  def match_by_order_reference
    return nil unless parsed_data[:order_reference].present?

    incoming_ref = normalize_order_reference(parsed_data[:order_reference])
    return nil if incoming_ref.blank?

    # First try exact match (fastest)
    exact_match = user.orders.find_by(order_reference: parsed_data[:order_reference])
    return exact_match if exact_match

    # Then try normalized matching against all user orders with references
    user.orders.where.not(order_reference: nil).find do |order|
      normalize_order_reference(order.order_reference) == incoming_ref
    end
  end

  # Normalize order reference for comparison
  # - Strips whitespace
  # - Converts to uppercase
  # - Removes common prefixes (Order #, Order:, Ref:, etc.)
  # - Removes special characters except alphanumeric and hyphens
  def normalize_order_reference(ref)
    return nil if ref.blank?

    normalized = ref.to_s.strip.upcase

    # Remove common prefixes
    prefixes = [
      /^ORDER\s*[#:\-]?\s*/i,
      /^ORD\s*[#:\-]?\s*/i,
      /^REF(?:ERENCE)?\s*[#:\-]?\s*/i,
      /^CONFIRMATION\s*[#:\-]?\s*/i,
      /^NUMBER\s*[#:\-]?\s*/i,
      /^NO\.?\s*[#:\-]?\s*/i,
      /^#\s*/
    ]

    prefixes.each { |prefix| normalized.gsub!(prefix, "") }

    # Remove any remaining special characters except alphanumeric and hyphens
    normalized.gsub(/[^A-Z0-9\-]/, "").presence
  end

  # Match if we've seen this tracking URL before
  def match_by_tracking_url
    return nil unless parsed_data[:tracking_urls].any?

    incoming_urls = parsed_data[:tracking_urls].map { |t| normalize_url(t[:url]) }

    # Find orders where any tracking URL matches (after normalization)
    user.orders.joins(:tracking_events).find do |order|
      order.tracking_events.any? do |event|
        incoming_urls.include?(normalize_url(event.tracking_url))
      end
    end
  end

  def normalize_url(url)
    return url if url.blank?

    uri = URI.parse(url)
    uri.scheme = "https" if uri.scheme == "http"
    uri.host = uri.host&.downcase&.sub(/^www\./, "")
    uri.port = nil if uri.port == 80 || uri.port == 443
    uri.path = uri.path.chomp("/") if uri.path && uri.path.length > 1
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    url.gsub(%r{^http://}i, "https://")
       .gsub(%r{^(https?://)www\.}i, '\1')
       .chomp("/")
  end

  # Match by same retailer within recent timeframe (7 days)
  # This catches "order shipped" emails that lack order reference
  def match_by_retailer_and_timeframe
    return nil unless parsed_data[:retailer_name].present?

    # Look for orders from same retailer in last 7 days without a tracking URL yet
    candidates = user.orders
        .left_joins(:tracking_events)
        .where(retailer_name: parsed_data[:retailer_name])
        .where(created_at: 7.days.ago..)
        .where(tracking_events: { id: nil }) # No tracking yet
        .order(created_at: :desc)

    # If the new email has an order reference, don't match an existing order
    # that has a DIFFERENT order reference (they're clearly separate orders)
    if parsed_data[:order_reference].present?
      candidates = candidates.where(
        "order_reference IS NULL OR order_reference = ?",
        parsed_data[:order_reference]
      )
    end

    candidates.first
  end
end
