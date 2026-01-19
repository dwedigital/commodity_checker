class ProcessInboundEmailJob < ApplicationJob
  queue_as :default

  def perform(inbound_email_id)
    inbound_email = InboundEmail.find(inbound_email_id)
    return if inbound_email.completed? || inbound_email.failed?

    inbound_email.update!(processing_status: :processing)

    # Step 1: Use AI to classify and extract email data
    classification = classify_email(inbound_email)
    Rails.logger.info("Email #{inbound_email.id} classified as: #{classification[:email_type]} (confidence: #{classification[:confidence]})")

    # Step 2: Use regex parser for tracking URLs (AI doesn't need to extract these)
    parser = EmailParserService.new(inbound_email)
    regex_data = parser.parse

    # Step 3: Merge AI classification with regex extraction
    parsed_data = merge_parsed_data(classification, regex_data)

    # Step 4: Process based on email type
    case classification[:email_type]
    when "order_confirmation"
      if classification[:contains_products] && classification[:products].any?
        process_order_data(inbound_email, parsed_data)
      else
        Rails.logger.info("Order confirmation without product details, skipping commodity processing")
        process_tracking_only(inbound_email, parsed_data) if parsed_data[:tracking_urls].any?
      end
    when "shipping_notification"
      Rails.logger.info("Shipping notification email - processing tracking only")
      process_tracking_only(inbound_email, parsed_data)
    when "delivery_confirmation"
      Rails.logger.info("Delivery confirmation email - updating tracking status")
      process_tracking_only(inbound_email, parsed_data)
    else
      Rails.logger.info("Email type '#{classification[:email_type]}' - no processing needed")
    end

    # Track email forwarded event
    track_analytics(inbound_email.user, "user_email_forwarded",
      email_id: inbound_email.id,
      email_type: classification[:email_type]
    )

    inbound_email.update!(processing_status: :completed, processed_at: Time.current)
  rescue => e
    Rails.logger.error("Failed to process inbound email #{inbound_email_id}: #{e.message}")
    inbound_email&.update!(processing_status: :failed)
    raise e
  end

  private

  def process_order_data(inbound_email, parsed_data)
    matcher = OrderMatcherService.new(inbound_email.user, parsed_data)
    existing_order = matcher.find_matching_order

    if existing_order
      update_existing_order(existing_order, inbound_email, parsed_data)
    else
      create_new_order(inbound_email, parsed_data)
    end
  end

  def update_existing_order(order, inbound_email, parsed_data)
    Rails.logger.info("Merging email #{inbound_email.id} into existing order #{order.id}")

    # Link this email to the order
    inbound_email.update!(order: order)

    # Update order reference if we didn't have one
    if order.order_reference.blank? && parsed_data[:order_reference].present?
      order.update!(order_reference: parsed_data[:order_reference])
    end

    # Update retailer if we didn't have one
    if order.retailer_name.blank? && parsed_data[:retailer_name].present?
      order.update!(retailer_name: parsed_data[:retailer_name])
    end

    # Filter to only real product descriptions
    real_products = parsed_data[:product_descriptions].select { |d| looks_like_product_description?(d) }

    # Get product images from email and match them to products using alt text
    email_images = parsed_data[:product_images] || []
    matched_images = match_images_to_products(email_images, real_products, inbound_email)

    # Add new product descriptions (avoid duplicates)
    add_new_items(order, real_products, matched_images)

    # Add new tracking URLs (avoid duplicates)
    add_new_tracking_urls(order, parsed_data[:tracking_urls])

    # Update status if we now have tracking
    if order.pending? && order.tracking_events.any?
      order.update!(status: :in_transit)
    end

    # Queue jobs if we added new data
    UpdateTrackingJob.perform_later(order.id) if parsed_data[:tracking_urls].any?
    SuggestCommodityCodesJob.perform_later(order.id) if real_products.any?

    order
  end

  def create_new_order(inbound_email, parsed_data)
    order = inbound_email.user.orders.create!(
      source_email: inbound_email,
      order_reference: parsed_data[:order_reference],
      retailer_name: parsed_data[:retailer_name],
      status: :pending
    )

    # Track order creation
    track_analytics(inbound_email.user, "order_created",
      order_id: order.id,
      retailer: order.retailer_name,
      source: "email"
    )

    # Link this email to the order
    inbound_email.update!(order: order)

    # Filter to only real product descriptions
    real_products = parsed_data[:product_descriptions].select { |d| looks_like_product_description?(d) }

    # Get product images from email and match them to products using alt text
    email_images = parsed_data[:product_images] || []
    matched_images = match_images_to_products(email_images, real_products, inbound_email)

    # Create order items from product descriptions
    if real_products.any?
      real_products.each_with_index do |description, index|
        # Assign image matched by alt text comparison
        image_url = matched_images[index]
        order.order_items.create!(
          description: description,
          quantity: 1,
          image_url: image_url
        )
      end
    elsif parsed_data[:tracking_urls].any?
      # This is a tracking-only email (e.g., "Your package has shipped")
      # Don't create placeholder items - wait for order confirmation email with products
      Rails.logger.info("Tracking-only email detected for order #{order.id}, no product items created")
    else
      # Create a placeholder item only if we have no tracking and no products
      # This handles edge cases where we want to track something
      order.order_items.create!(
        description: "Item from #{parsed_data[:retailer_name] || 'order'}",
        quantity: 1
      )
    end

    # Create tracking events from URLs
    parsed_data[:tracking_urls].each do |tracking_info|
      order.tracking_events.create!(
        carrier: tracking_info[:carrier],
        tracking_url: tracking_info[:url],
        status: "Tracking link found",
        event_timestamp: Time.current
      )
    end

    # Queue tracking job if we have tracking URLs
    UpdateTrackingJob.perform_later(order.id) if parsed_data[:tracking_urls].any?

    # Only process products if we have real product items (not tracking-only emails)
    if order.order_items.any?
      # Queue commodity code suggestion
      SuggestCommodityCodesJob.perform_later(order.id)

      # Queue product page scraping if product URLs found
      if parsed_data[:product_urls].any?
        schedule_product_scraping(order, parsed_data[:product_urls])
      else
        # No product URLs in email - try to find them by searching retailer site
        search_and_scrape_products(order, parsed_data[:retailer_name])
      end
    else
      Rails.logger.info("No product items to process for order #{order.id} (tracking-only email)")
    end

    order
  end

  def search_and_scrape_products(order, retailer_name)
    return if retailer_name.blank?

    # Only search if we have product descriptions that look like actual products
    # Skip for delivery/tracking emails that don't contain product details
    items_to_search = order.order_items.select { |item| looks_like_product_description?(item.description) }

    return if items_to_search.empty?

    Rails.logger.info("Searching for product info: #{items_to_search.length} items via AI web search")

    finder = ProductInfoFinderService.new

    items_to_search.each do |item|
      next if item.scraped_description.present?  # Already have detailed info

      # Use AI + web search to find detailed product information
      product_info = finder.find(
        product_name: item.description,
        retailer: retailer_name
      )

      if product_info && product_info[:found]
        # Build enhanced description from found info
        enhanced_desc = finder.build_description_for_classification(product_info)

        Rails.logger.info("Found product info for '#{item.description}': #{product_info[:product_name]}")

        # Only use Tavily image if we don't already have one from the email
        update_attrs = {
          scraped_description: enhanced_desc,
          product_url: product_info[:product_url]
        }
        update_attrs[:image_url] = product_info[:image_url] if item.image_url.blank? && product_info[:image_url].present?

        item.update!(update_attrs)

        # Re-run commodity code suggestion with enhanced description
        suggester = LlmCommoditySuggester.new
        suggestion = suggester.suggest(enhanced_desc)

        if suggestion && suggestion[:commodity_code].present?
          item.update!(
            suggested_commodity_code: suggestion[:commodity_code],
            commodity_code_confidence: suggestion[:confidence],
            llm_reasoning: build_suggestion_reasoning(suggestion)
          )
          Rails.logger.info("Updated commodity code for '#{item.description}': #{suggestion[:commodity_code]}")
        end
      else
        Rails.logger.info("Could not find detailed info for '#{item.description}'")
      end
    end
  rescue => e
    Rails.logger.error("Error searching for product info: #{e.message}")
    # Don't fail the job, just continue without enhanced info
  end

  def build_suggestion_reasoning(suggestion)
    parts = []
    parts << suggestion[:reasoning] if suggestion[:reasoning].present?
    parts << "Category: #{suggestion[:category]}" if suggestion[:category].present?
    parts << "Official: #{suggestion[:official_description]}" if suggestion[:official_description].present?
    parts << "(Validated)" if suggestion[:validated]
    parts << "(Unvalidated - code may need verification)" if suggestion[:validated] == false

    parts.join(" | ")
  end

  def looks_like_product_description?(description)
    return false if description.blank?

    # Filter out generic/placeholder descriptions
    generic_patterns = [
      /^item from/i,
      /^your (order|package|shipment|delivery)/i,
      /^order #?\d+/i,
      /^package/i,
      /^shipment/i,
      /^delivery/i,
      /^tracking/i,
      /^parcel/i
    ]

    return false if generic_patterns.any? { |p| description.match?(p) }

    # Should have a reasonable length (actual product name)
    return false if description.length < 5
    return false if description.length > 200

    # Should contain letters (not just numbers/symbols)
    return false unless description.match?(/[a-zA-Z]{3,}/)

    true
  end

  def schedule_product_scraping(order, product_urls)
    return if product_urls.blank?

    # Try to match product URLs to order items
    order.order_items.each do |item|
      next if item.product_url.present?

      # Find a matching product URL (simple heuristic - use first available)
      matching_url = product_urls.shift
      break unless matching_url

      item.update!(product_url: matching_url[:url])
      ScrapeProductPageJob.perform_later(order_item_id: item.id)
    end
  end

  def add_new_items(order, descriptions, images = [])
    return if descriptions.blank?

    existing_descriptions = order.order_items.pluck(:description).map(&:downcase)

    descriptions.each_with_index do |desc, index|
      next if existing_descriptions.include?(desc.downcase)
      image_url = images[index]
      order.order_items.create!(description: desc, quantity: 1, image_url: image_url)
    end
  end

  def add_new_tracking_urls(order, tracking_urls)
    return if tracking_urls.blank?

    existing_urls = order.tracking_events.pluck(:tracking_url)

    tracking_urls.each do |tracking_info|
      next if existing_urls.include?(tracking_info[:url])

      order.tracking_events.create!(
        carrier: tracking_info[:carrier],
        tracking_url: tracking_info[:url],
        status: "Tracking link found",
        event_timestamp: Time.current
      )
    end
  end

  # AI-based email classification
  def classify_email(inbound_email)
    classifier = EmailClassifierService.new
    classifier.classify(
      email_subject: inbound_email.subject,
      email_body: inbound_email.body_text,
      from_address: inbound_email.from_address
    )
  rescue => e
    Rails.logger.error("Email classification failed: #{e.message}, falling back to regex parsing")
    # Return a default that triggers regex-based processing
    {
      email_type: "order_confirmation",
      confidence: 0.0,
      contains_products: false,
      products: [],
      retailer: nil,
      order_reference: nil,
      reasoning: "Classification failed, using fallback"
    }
  end

  # Merge AI classification with regex-extracted data
  def merge_parsed_data(classification, regex_data)
    # Build product descriptions from AI-extracted products
    ai_products = classification[:products].map do |p|
      parts = [ p[:name] ]
      parts << "Brand: #{p[:brand]}" if p[:brand].present?
      parts << "Color: #{p[:color]}" if p[:color].present?
      parts << "Material: #{p[:material]}" if p[:material].present?
      parts.join(" - ")
    end.compact

    {
      # Use AI-extracted products if available, otherwise fall back to regex
      product_descriptions: ai_products.any? ? ai_products : regex_data[:product_descriptions],
      # Always use regex for tracking URLs (more reliable for URL extraction)
      tracking_urls: regex_data[:tracking_urls],
      # Prefer AI for order reference, fall back to regex
      order_reference: classification[:order_reference] || regex_data[:order_reference],
      # Prefer AI for retailer, fall back to regex
      retailer_name: classification[:retailer] || regex_data[:retailer_name],
      # Pass through product URLs from regex
      product_urls: regex_data[:product_urls],
      # Pass through product images from HTML parsing
      product_images: regex_data[:product_images] || []
    }
  end

  # Process email that only has tracking info (no products)
  def process_tracking_only(inbound_email, parsed_data)
    return unless parsed_data[:tracking_urls].any?

    # Try to find existing order to attach tracking to
    matcher = OrderMatcherService.new(inbound_email.user, parsed_data)
    existing_order = matcher.find_matching_order

    if existing_order
      Rails.logger.info("Adding tracking to existing order #{existing_order.id}")

      # Link this email to the order
      inbound_email.update!(order: existing_order)

      add_new_tracking_urls(existing_order, parsed_data[:tracking_urls])

      if existing_order.pending? && existing_order.tracking_events.any?
        existing_order.update!(status: :in_transit)
      end

      UpdateTrackingJob.perform_later(existing_order.id)
    else
      # Create order just for tracking (no product items)
      order = inbound_email.user.orders.create!(
        source_email: inbound_email,
        order_reference: parsed_data[:order_reference],
        retailer_name: parsed_data[:retailer_name],
        status: :in_transit
      )

      # Link this email to the order
      inbound_email.update!(order: order)

      parsed_data[:tracking_urls].each do |tracking_info|
        order.tracking_events.create!(
          carrier: tracking_info[:carrier],
          tracking_url: tracking_info[:url],
          status: "Tracking link found",
          event_timestamp: Time.current
        )
      end

      UpdateTrackingJob.perform_later(order.id)
      Rails.logger.info("Created tracking-only order #{order.id}")
    end
  end

  # Match images to products using alt text comparison
  # Falls back to position-based matching if no alt text matches found
  def match_images_to_products(images, product_descriptions, inbound_email)
    return [] if images.blank? || product_descriptions.blank?

    # Use EmailParserService to match images to products
    parser = EmailParserService.new(inbound_email)
    matched = parser.match_images_to_products(images, product_descriptions)

    # If smart matching found no results, fall back to position-based
    if matched.all?(&:nil?)
      Rails.logger.info("No alt text matches found, falling back to position-based image assignment")
      return images.first(product_descriptions.length).map { |img| img[:url] }
    end

    matched
  end

  def track_analytics(user, event_name, properties = {})
    AnalyticsTracker.new(user: user).track(event_name, properties)
  rescue => e
    Rails.logger.error("Analytics tracking failed: #{e.message}")
  end
end
