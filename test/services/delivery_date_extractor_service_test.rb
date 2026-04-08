require "test_helper"

class DeliveryDateExtractorServiceTest < ActiveSupport::TestCase
  def setup
    # Use a fixed date for predictable testing (Thursday, January 22, 2026)
    @email_date = Date.new(2026, 1, 22)
  end

  # ===========================================
  # Explicit ISO Date Extraction
  # ===========================================

  test "extracts ISO format date" do
    body = "Your order will arrive soon.\nEstimated delivery date: 2026-01-28\nThank you!"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
    assert_equal :explicit_date, result[:source]
    assert_equal 0.9, result[:confidence]
  end

  test "extracts delivery by ISO date" do
    body = "Delivery by 2026-02-05"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 2, 5), result[:estimated_delivery]
  end

  # ===========================================
  # UK/US Date Formats
  # ===========================================

  test "extracts UK format date (dd/mm/yyyy)" do
    body = "Estimated delivery: 28/01/2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts date with dashes (dd-mm-yyyy)" do
    body = "Delivery date: 28-01-2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  # ===========================================
  # Natural Language Dates
  # ===========================================

  test "extracts natural language date with year" do
    body = "Your package is arriving January 28, 2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts abbreviated month name" do
    body = "Expected delivery: Jan 28, 2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts date with ordinal suffix" do
    body = "Arriving January 28th, 2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts UK style natural date (day before month)" do
    body = "Expected: 28 January 2026"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts date without year, assumes current year" do
    body = "Arriving January 28"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
  end

  test "extracts date without year, rolls to next year if past" do
    # Email date is Jan 23, 2026. "January 20" should roll to 2027
    body = "Arriving January 20"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2027, 1, 20), result[:estimated_delivery]
  end

  # ===========================================
  # Relative Dates
  # ===========================================

  test "extracts tomorrow" do
    body = "Your package will arrive tomorrow"
    result = extract(body)

    assert_not_nil result
    assert_equal @email_date + 1.day, result[:estimated_delivery]
  end

  test "extracts today" do
    body = "Delivery expected today"
    result = extract(body)

    assert_not_nil result
    assert_equal @email_date, result[:estimated_delivery]
  end

  test "extracts this Friday" do
    # Email date is Thursday Jan 22, 2026. "this Friday" = Jan 23
    body = "Arriving this Friday"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 23), result[:estimated_delivery]
  end

  test "extracts next Monday" do
    # Email date is Thursday Jan 22, 2026. "next Monday" = Jan 26
    body = "Expected next Monday"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 26), result[:estimated_delivery]
  end

  # ===========================================
  # Day of Week
  # ===========================================

  test "extracts day of week - Friday" do
    # Email date is Thursday Jan 22, 2026. "Friday" = Jan 23
    body = "Arriving Friday"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 23), result[:estimated_delivery]
  end

  test "extracts day of week - same day assumes next week" do
    # Email date is Thursday Jan 22, 2026. "Thursday" = Jan 29 (next week)
    body = "Delivery expected Thursday"
    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 29), result[:estimated_delivery]
  end

  # ===========================================
  # Shipping Method Calculations
  # ===========================================

  test "calculates delivery from Royal Mail 1st Class" do
    body = "Shipped via Royal Mail 1st Class"
    result = extract(body)

    assert_not_nil result
    assert_equal :shipping_method, result[:source]
    assert_equal "royal_mail/first_class", result[:shipping_method]
    assert_equal 0.7, result[:confidence]
    # 1 business day from Thursday Jan 22 = Friday Jan 23
    assert_equal Date.new(2026, 1, 23), result[:estimated_delivery]
  end

  test "calculates delivery from Royal Mail 2nd Class" do
    body = "Shipping: Royal Mail 2nd Class"
    result = extract(body)

    assert_not_nil result
    assert_equal "royal_mail/second_class", result[:shipping_method]
    # 2 business days from Thursday Jan 22 = Monday Jan 26 (Friday + skips weekend)
    assert_equal Date.new(2026, 1, 26), result[:estimated_delivery]
  end

  test "calculates delivery from DPD next day" do
    body = "Your order is being shipped by DPD next day delivery"
    result = extract(body)

    assert_not_nil result
    assert_equal "dpd/next_day", result[:shipping_method]
    # 1 business day from Thursday Jan 22 = Friday Jan 23
    assert_equal Date.new(2026, 1, 23), result[:estimated_delivery]
  end

  test "calculates delivery from Amazon Prime" do
    body = "Shipped with Amazon Prime - FREE One-Day Delivery"
    result = extract(body)

    assert_not_nil result
    assert_equal "amazon/next_day", result[:shipping_method]
  end

  test "calculates delivery from generic express shipping" do
    body = "Express shipping selected"
    result = extract(body)

    assert_not_nil result
    assert_equal "generic/express", result[:shipping_method]
    assert_equal 0.6, result[:confidence] # Lower for generic
  end

  test "calculates delivery from generic standard shipping" do
    body = "Standard delivery"
    result = extract(body)

    assert_not_nil result
    assert_equal "generic/standard", result[:shipping_method]
    # 3 business days from Thursday Jan 22 = Tuesday Jan 27 (Fri, Mon, Tue - skips weekend)
    assert_equal Date.new(2026, 1, 27), result[:estimated_delivery]
  end

  # ===========================================
  # Day Range Extraction
  # ===========================================

  test "extracts day range (3-5 business days)" do
    body = "Delivery in 3-5 business days"
    result = extract(body)

    assert_not_nil result
    assert_equal :day_range, result[:source]
    assert_equal 0.6, result[:confidence]
    # Uses minimum (3 business days) from Thursday Jan 22 = Tuesday Jan 27 (Fri, Mon, Tue)
    assert_equal Date.new(2026, 1, 27), result[:estimated_delivery]
  end

  test "extracts within X days" do
    body = "Arrives within 2 business days"
    result = extract(body)

    assert_not_nil result
    # 2 business days from Thursday Jan 22 = Monday Jan 26 (Fri, Mon)
    assert_equal Date.new(2026, 1, 26), result[:estimated_delivery]
  end

  test "extracts arrives in X days" do
    body = "Your package arrives in 5 days"
    result = extract(body)

    assert_not_nil result
    # 5 business days from Thursday Jan 22 = Thursday Jan 29 (Fri, Mon, Tue, Wed, Thu)
    assert_equal Date.new(2026, 1, 29), result[:estimated_delivery]
  end

  test "extracts X to Y days" do
    body = "Delivery: 2 to 3 working days"
    result = extract(body)

    assert_not_nil result
    # 2 business days from Thursday Jan 22 = Monday Jan 26 (Fri, Mon)
    assert_equal Date.new(2026, 1, 26), result[:estimated_delivery]
  end

  # ===========================================
  # Weekend Skipping
  # ===========================================

  test "skips weekends when calculating business days" do
    # Jan 23, 2026 is a Friday
    friday_email_date = Date.new(2026, 1, 23)

    body = "Delivery in 2 business days"
    result = DeliveryDateExtractorService.new(
      email_body: body,
      email_date: friday_email_date
    ).extract

    assert_not_nil result
    # 2 business days from Friday Jan 23 = Tuesday Jan 27 (skips Sat Jan 24 / Sun Jan 25)
    assert_equal Date.new(2026, 1, 27), result[:estimated_delivery]
  end

  # ===========================================
  # Priority Order
  # ===========================================

  test "explicit date takes priority over shipping method" do
    body = "Shipped via Royal Mail 1st Class. Estimated delivery: January 30, 2026"
    result = extract(body)

    assert_not_nil result
    assert_equal :explicit_date, result[:source]
    assert_equal Date.new(2026, 1, 30), result[:estimated_delivery]
    assert_equal 0.9, result[:confidence]
  end

  test "shipping method takes priority over day range" do
    body = "Royal Mail 2nd Class - arrives in 3-5 business days"
    result = extract(body)

    assert_not_nil result
    assert_equal :shipping_method, result[:source]
  end

  # ===========================================
  # Edge Cases
  # ===========================================

  test "returns nil when no delivery info found" do
    body = "Thank you for your order! We'll notify you when it ships."
    result = extract(body)

    assert_nil result
  end

  test "returns nil for empty body" do
    result = extract("")
    assert_nil result
  end

  test "returns nil for nil body" do
    result = DeliveryDateExtractorService.new(
      email_body: nil,
      email_date: @email_date
    ).extract

    assert_nil result
  end

  test "discards date in the past" do
    body = "Delivery date: 2026-01-20" # Before email date of Jan 22
    result = extract(body)

    assert_nil result
  end

  test "handles very large day range gracefully" do
    body = "Delivery in 50 days" # Should be rejected (> 30)
    result = extract(body)

    assert_nil result
  end

  test "handles malformed date gracefully" do
    body = "Delivery date: not-a-date"
    result = extract(body)

    assert_nil result
  end

  # ===========================================
  # Real-World Email Examples
  # ===========================================

  test "extracts from Amazon shipping confirmation" do
    body = <<~EMAIL
      Your Amazon.co.uk order has been dispatched!

      Track your package: Track Package

      Order #123-4567890-1234567

      Arriving tomorrow by 10pm
      Prime

      Apple iPhone 15 Pro Case
      Sold by: Apple Store

      Delivery address:
      123 High Street
      London
    EMAIL

    result = extract(body)

    assert_not_nil result
    assert_equal @email_date + 1.day, result[:estimated_delivery]
  end

  test "extracts from ASOS shipping email" do
    body = <<~EMAIL
      Great news! Your ASOS order is on its way.

      Order Number: 123456789
      Shipping: Royal Mail Tracked 48

      Your order should arrive within 2 working days.

      Black Oversized T-Shirt
      Size: M
    EMAIL

    result = extract(body)

    assert_not_nil result
    assert_equal "royal_mail/tracked_48", result[:shipping_method]
  end

  test "extracts from standard shipping confirmation" do
    body = <<~EMAIL
      Order Confirmation

      Thank you for your order!

      ESTIMATED DELIVERY DATE: 2026-01-28

      Items:
      - Blue Cotton T-Shirt (x1)

      Shipping Method: Standard Delivery
    EMAIL

    result = extract(body)

    assert_not_nil result
    assert_equal Date.new(2026, 1, 28), result[:estimated_delivery]
    assert_equal :explicit_date, result[:source]
  end

  private

  def extract(body)
    DeliveryDateExtractorService.new(
      email_body: body,
      email_date: @email_date
    ).extract
  end
end
