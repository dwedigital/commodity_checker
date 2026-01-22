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
  def match_by_order_reference
    return nil unless parsed_data[:order_reference].present?

    user.orders.find_by(order_reference: parsed_data[:order_reference])
  end

  # Match if we've seen this tracking URL before
  def match_by_tracking_url
    return nil unless parsed_data[:tracking_urls].any?

    urls = parsed_data[:tracking_urls].map { |t| t[:url] }

    user.orders
        .joins(:tracking_events)
        .where(tracking_events: { tracking_url: urls })
        .first
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
