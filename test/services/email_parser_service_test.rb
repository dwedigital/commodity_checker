# frozen_string_literal: true

require "test_helper"
require "ostruct"

class EmailParserServiceTest < ActiveSupport::TestCase
  # Helper to create mock email objects for testing
  def build_email(subject: "Test Email", from_address: "test@example.com", body_text: "", body_html: nil)
    OpenStruct.new(
      subject: subject,
      from_address: from_address,
      body_text: body_text,
      body_html: body_html
    )
  end

  # =============================================================================
  # Tracking URL Extraction
  # =============================================================================

  test "extracts Royal Mail tracking URL" do
    email = build_email(
      body_text: "Track your parcel: https://www.royalmail.com/track-your-item?trackNumber=AB123456789GB"
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    assert urls.any? { |u| u[:carrier] == "royal_mail" }
    assert urls.any? { |u| u[:url].include?("royalmail.com") }
  end

  test "extracts DHL tracking URL" do
    email = build_email(
      body_text: "Your shipment is on the way: https://www.dhl.co.uk/en/express/tracking.html?AWB=1234567890"
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    assert urls.any? { |u| u[:carrier] == "dhl" }
  end

  test "extracts Amazon tracking URL" do
    email = build_email(
      body_text: "Track your package: https://www.amazon.co.uk/progress-tracker/package/ref=xyz"
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    assert urls.any? { |u| u[:carrier] == "amazon" }
  end

  test "extracts Global-e tracking URL from HTML link" do
    email = build_email(
      body_text: "Global-e tracking number: LTN429578213 https://web.global-e.com/track/abc123",
      body_html: '<a href="https://web.global-e.com/track/abc123">Track your order</a>'
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    assert urls.any? { |u| u[:carrier] == "global_e" }
  end

  test "extracts multiple tracking URLs from same email" do
    email = build_email(
      body_text: <<~TEXT
        Your order has been split into two shipments:
        Shipment 1: https://www.royalmail.com/track-your-item?trackNumber=AB123
        Shipment 2: https://www.dhl.co.uk/tracking?AWB=456
      TEXT
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    # Should find both carrier URLs (may also match generic patterns)
    assert urls.length >= 2
    carriers = urls.map { |u| u[:carrier] }
    assert_includes carriers, "royal_mail"
    assert_includes carriers, "dhl"
  end

  test "deduplicates identical tracking URLs" do
    email = build_email(
      body_text: "Track here: https://www.royalmail.com/track?id=123 or here: https://www.royalmail.com/track?id=123"
    )
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls
    unique_urls = urls.map { |u| u[:url] }.uniq

    # URLs should be deduplicated
    assert_equal urls.length, unique_urls.length
  end

  test "returns empty array when no tracking URLs present" do
    email = build_email(body_text: "Thank you for your order!")
    parser = EmailParserService.new(email)

    urls = parser.extract_tracking_urls

    assert_equal [], urls
  end

  # =============================================================================
  # Order Reference Extraction
  # =============================================================================

  test "extracts order number with hash format" do
    email = build_email(body_text: "Your order #ABC123456 has shipped")
    parser = EmailParserService.new(email)

    assert_equal "ABC123456", parser.extract_order_reference
  end

  test "extracts order number with colon format" do
    email = build_email(body_text: "Order Number: DEF789012")
    parser = EmailParserService.new(email)

    assert_equal "DEF789012", parser.extract_order_reference
  end

  test "extracts reference number format" do
    email = build_email(body_text: "Reference: REF-2024-001234")
    parser = EmailParserService.new(email)

    assert_equal "REF-2024-001234", parser.extract_order_reference
  end

  test "extracts tracking number format" do
    email = build_email(body_text: "Tracking Number: TRK123456789")
    parser = EmailParserService.new(email)

    assert_equal "TRK123456789", parser.extract_order_reference
  end

  test "returns nil when no order reference found" do
    email = build_email(body_text: "Thank you for shopping with us!")
    parser = EmailParserService.new(email)

    assert_nil parser.extract_order_reference
  end

  test "extracts first matching order reference" do
    email = build_email(body_text: "Order #FIRST123 confirmed. Reference: SECOND456")
    parser = EmailParserService.new(email)

    assert_equal "FIRST123", parser.extract_order_reference
  end

  # =============================================================================
  # Retailer Identification
  # =============================================================================

  test "identifies Amazon from email address" do
    email = build_email(from_address: "shipping@amazon.co.uk")
    parser = EmailParserService.new(email)

    assert_equal "Amazon", parser.identify_retailer
  end

  test "identifies ASOS from email address" do
    email = build_email(from_address: "orders@asos.com")
    parser = EmailParserService.new(email)

    assert_equal "ASOS", parser.identify_retailer
  end

  test "identifies retailer from email body when from address is generic" do
    email = build_email(
      from_address: "noreply@mail.example.com",
      body_text: "Thank you for shopping at www.johnlewis.com"
    )
    parser = EmailParserService.new(email)

    assert_equal "John Lewis", parser.identify_retailer
  end

  test "identifies retailer from forwarded email original sender" do
    email = build_email(
      from_address: "user@gmail.com",
      body_text: <<~TEXT
        ---------- Forwarded message ----------
        From: orders@zara.com
        Date: Mon, 15 Jan 2024
        Subject: Your Zara order

        Thank you for your order!
      TEXT
    )
    parser = EmailParserService.new(email)

    assert_equal "Zara", parser.identify_retailer
  end

  test "extracts retailer name from unknown domain" do
    email = build_email(from_address: "orders@boutique-clothing.com")
    parser = EmailParserService.new(email)

    assert_equal "Boutique Clothing", parser.identify_retailer
  end

  test "cleans up noreply prefix from domain" do
    email = build_email(from_address: "noreply@orders.fashionstore.com")
    parser = EmailParserService.new(email)

    # Should extract "Fashionstore" not "Orders Fashionstore"
    retailer = parser.identify_retailer
    assert retailer.present?
    refute retailer.downcase.include?("orders")
  end

  # =============================================================================
  # Product Description Extraction
  # =============================================================================

  test "extracts product with color attribute" do
    email = build_email(
      body_text: <<~TEXT
        Your order:
        Classic Cotton T-Shirt
        Color: Navy Blue
        Size: M
        Qty: 1
      TEXT
    )
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    assert descriptions.any? { |d| d.include?("Classic Cotton T-Shirt") }
    assert descriptions.any? { |d| d.include?("Navy Blue") }
  end

  test "extracts product from bullet list" do
    email = build_email(
      body_text: <<~TEXT
        Items in your order:
        - Wireless Bluetooth Headphones
        - USB-C Charging Cable
        - Phone Case
      TEXT
    )
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    assert descriptions.any? { |d| d.include?("Wireless Bluetooth Headphones") }
    assert descriptions.any? { |d| d.include?("USB-C Charging Cable") }
  end

  test "extracts product from quantity pattern" do
    email = build_email(body_text: "2x Premium Leather Wallet")
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    assert descriptions.any? { |d| d.include?("Premium Leather Wallet") }
  end

  test "filters out non-product lines" do
    email = build_email(
      body_text: <<~TEXT
        Order details:
        Subtotal: £50.00
        Shipping: £3.99
        Total: £53.99
        Thank you for your order!
      TEXT
    )
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    refute descriptions.any? { |d| d.include?("Subtotal") }
    refute descriptions.any? { |d| d.include?("Shipping") }
    refute descriptions.any? { |d| d.include?("Total") }
    refute descriptions.any? { |d| d.include?("Thank you") }
  end

  test "removes prices from product descriptions" do
    email = build_email(
      body_text: <<~TEXT
        Cotton Sweater
        Color: Grey
        £45.99
      TEXT
    )
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    # Should have the product but not the price
    refute descriptions.any? { |d| d.include?("45.99") }
  end

  test "limits product descriptions to 10 items" do
    products = (1..15).map { |i| "- Product Item #{i}" }.join("\n")
    email = build_email(body_text: products)
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    assert descriptions.length <= 10
  end

  test "deduplicates similar product descriptions" do
    email = build_email(
      body_text: <<~TEXT
        - Cotton T-Shirt
        - cotton t-shirt
        - COTTON T-SHIRT
      TEXT
    )
    parser = EmailParserService.new(email)

    descriptions = parser.extract_product_descriptions

    # Should deduplicate case-insensitively
    assert_equal 1, descriptions.length
  end

  # =============================================================================
  # Product Image Extraction
  # =============================================================================

  test "extracts product images from HTML" do
    email = build_email(
      body_html: <<~HTML
        <html>
          <img src="https://example.com/products/shirt.jpg" width="200" height="200" alt="Blue Shirt">
          <img src="https://example.com/products/pants.jpg" width="150" height="150" alt="Black Pants">
        </html>
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert_equal 2, images.length
    # Images now return objects with url, alt_text, width, height
    assert images.any? { |img| img[:url].include?("shirt.jpg") }
    assert images.any? { |img| img[:url].include?("pants.jpg") }
    # Alt text is extracted
    shirt_img = images.find { |img| img[:url].include?("shirt.jpg") }
    assert_equal "Blue Shirt", shirt_img[:alt_text]
  end

  test "filters out logo images" do
    email = build_email(
      body_html: <<~HTML
        <img src="https://example.com/logo.png" width="100" height="50">
        <img src="https://example.com/products/item.jpg" width="200" height="200">
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    refute images.any? { |img| img[:url].include?("logo") }
    assert images.any? { |img| img[:url].include?("item.jpg") }
  end

  test "filters out social media icons" do
    email = build_email(
      body_html: <<~HTML
        <img src="https://example.com/facebook-icon.png" width="32" height="32">
        <img src="https://example.com/twitter.png" width="32" height="32">
        <img src="https://example.com/instagram.png" width="32" height="32">
        <img src="https://example.com/products/dress.jpg" width="200" height="300">
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert_equal 1, images.length
    assert images.first[:url].include?("dress.jpg")
  end

  test "filters out tracking pixels" do
    email = build_email(
      body_html: <<~HTML
        <img src="https://tracking.example.com/pixel.gif" width="1" height="1">
        <img src="https://example.com/beacon.png" width="1" height="1">
        <img src="https://example.com/products/shoes.jpg" width="200" height="200">
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    refute images.any? { |img| img[:url].include?("pixel") || img[:url].include?("beacon") }
  end

  test "filters out small images by dimension" do
    email = build_email(
      body_html: <<~HTML
        <img src="https://example.com/tiny-icon.png" width="24" height="24">
        <img src="https://example.com/products/bag.jpg" width="150" height="200">
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert_equal 1, images.length
    assert images.first[:url].include?("bag.jpg")
  end

  test "sorts images by size descending" do
    email = build_email(
      body_html: <<~HTML
        <img src="https://example.com/small.jpg" width="100" height="100">
        <img src="https://example.com/large.jpg" width="400" height="400">
        <img src="https://example.com/medium.jpg" width="200" height="200">
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert_equal "https://example.com/large.jpg", images.first[:url]
  end

  test "returns empty array when no HTML body" do
    email = build_email(body_text: "Plain text email", body_html: nil)
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert_equal [], images
  end

  test "limits images to 10 items" do
    img_tags = (1..15).map { |i| %(<img src="https://example.com/product#{i}.jpg" width="200" height="200">) }.join
    email = build_email(body_html: "<html>#{img_tags}</html>")
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    assert images.length <= 10
  end

  # =============================================================================
  # Image to Product Matching
  # =============================================================================

  test "matches images to products using alt text" do
    email = build_email(
      body_html: <<~HTML
        <html>
          <img src="https://example.com/sandal.jpg" width="200" height="200" alt="Area Sandal - Beige">
          <img src="https://example.com/sneaker.jpg" width="200" height="200" alt="Dice Lo Sneaker - Green">
          <img src="https://example.com/logo.png" width="100" height="100" alt="Brand Logo">
        </html>
      HTML
    )
    parser = EmailParserService.new(email)
    images = parser.extract_product_images

    products = [
      "Dice Lo Sneaker - Color: Light Green/Off White",
      "Area Sandal - Color: Beige/Beige"
    ]

    matched = parser.match_images_to_products(images, products)

    assert_equal 2, matched.length
    # Dice Lo Sneaker should match the sneaker image
    assert matched[0].include?("sneaker.jpg")
    # Area Sandal should match the sandal image
    assert matched[1].include?("sandal.jpg")
  end

  test "returns nil for unmatched products" do
    email = build_email(
      body_html: <<~HTML
        <html>
          <img src="https://example.com/shirt.jpg" width="200" height="200" alt="Blue Shirt">
        </html>
      HTML
    )
    parser = EmailParserService.new(email)
    images = parser.extract_product_images

    products = [ "Blue Shirt", "Red Pants" ]  # Red Pants has no matching image

    matched = parser.match_images_to_products(images, products)

    assert_equal 2, matched.length
    assert matched[0].include?("shirt.jpg")  # Shirt matched
    assert_nil matched[1]                     # Pants not matched
  end

  test "filters images with non-product alt text like logo" do
    email = build_email(
      body_html: <<~HTML
        <html>
          <img src="https://example.com/brand.png" width="100" height="100" alt="Company Logo">
          <img src="https://example.com/shirt.jpg" width="200" height="200" alt="Cotton T-Shirt">
        </html>
      HTML
    )
    parser = EmailParserService.new(email)

    images = parser.extract_product_images

    # Only the shirt should be extracted, logo filtered by alt text
    assert_equal 1, images.length
    assert images.first[:url].include?("shirt.jpg")
  end

  # =============================================================================
  # Full Parse Integration
  # =============================================================================

  test "parse returns complete hash with all fields" do
    email = build_email(
      subject: "Your Amazon order has shipped",
      from_address: "shipping@amazon.co.uk",
      body_text: <<~TEXT
        Order #AMZ-123-456 has shipped!

        Items:
        - Echo Dot Smart Speaker
        Color: Charcoal

        Track your package:
        https://www.amazon.co.uk/progress-tracker/package/ref=xyz
      TEXT
    )
    parser = EmailParserService.new(email)

    result = parser.parse

    assert result.is_a?(Hash)
    assert result.key?(:tracking_urls)
    assert result.key?(:order_reference)
    assert result.key?(:retailer_name)
    assert result.key?(:product_descriptions)
    assert result.key?(:product_images)

    assert result[:tracking_urls].any?
    assert_equal "AMZ-123-456", result[:order_reference]
    assert_equal "Amazon", result[:retailer_name]
    assert result[:product_descriptions].any? { |d| d.include?("Echo Dot") }
  end
end
