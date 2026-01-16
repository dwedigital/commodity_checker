class ProcessInboundEmailJob < ApplicationJob
  queue_as :default

  def perform(inbound_email_id)
    inbound_email = InboundEmail.find(inbound_email_id)
    return if inbound_email.completed? || inbound_email.failed?

    inbound_email.update!(processing_status: :processing)

    parser = EmailParserService.new(inbound_email)
    parsed_data = parser.parse

    if parsed_data[:tracking_urls].any? || parsed_data[:order_reference].present? || parsed_data[:product_descriptions].any?
      process_order_data(inbound_email, parsed_data)
      inbound_email.update!(processing_status: :completed, processed_at: Time.current)
    else
      Rails.logger.info("No useful data found in email #{inbound_email.id}")
      inbound_email.update!(processing_status: :completed, processed_at: Time.current)
    end
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

    # Update order reference if we didn't have one
    if order.order_reference.blank? && parsed_data[:order_reference].present?
      order.update!(order_reference: parsed_data[:order_reference])
    end

    # Update retailer if we didn't have one
    if order.retailer_name.blank? && parsed_data[:retailer_name].present?
      order.update!(retailer_name: parsed_data[:retailer_name])
    end

    # Add new product descriptions (avoid duplicates)
    add_new_items(order, parsed_data[:product_descriptions])

    # Add new tracking URLs (avoid duplicates)
    add_new_tracking_urls(order, parsed_data[:tracking_urls])

    # Update status if we now have tracking
    if order.pending? && order.tracking_events.any?
      order.update!(status: :in_transit)
    end

    # Queue jobs if we added new data
    UpdateTrackingJob.perform_later(order.id) if parsed_data[:tracking_urls].any?
    SuggestCommodityCodesJob.perform_later(order.id) if parsed_data[:product_descriptions].any?

    order
  end

  def create_new_order(inbound_email, parsed_data)
    order = inbound_email.user.orders.create!(
      source_email: inbound_email,
      order_reference: parsed_data[:order_reference],
      retailer_name: parsed_data[:retailer_name],
      status: :pending
    )

    # Create order items from product descriptions
    if parsed_data[:product_descriptions].any?
      parsed_data[:product_descriptions].each do |description|
        order.order_items.create!(description: description, quantity: 1)
      end
    else
      # Create a placeholder item if no products found
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

    # Queue jobs
    UpdateTrackingJob.perform_later(order.id) if parsed_data[:tracking_urls].any?
    SuggestCommodityCodesJob.perform_later(order.id)

    # Queue product page scraping if product URLs found
    schedule_product_scraping(order, parsed_data[:product_urls]) if parsed_data[:product_urls].any?

    order
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

  def add_new_items(order, descriptions)
    return if descriptions.blank?

    existing_descriptions = order.order_items.pluck(:description).map(&:downcase)

    descriptions.each do |desc|
      next if existing_descriptions.include?(desc.downcase)
      order.order_items.create!(description: desc, quantity: 1)
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
end
