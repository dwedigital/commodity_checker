class UpdateTrackingJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    scraper = TrackingScraperService.new
    any_updates = false

    order.tracking_events.where.not(tracking_url: nil).each do |event|
      result = update_tracking_status(event, scraper)
      any_updates = true if result

      # Rate limit between requests
      sleep(1)
    end

    # Update order status based on tracking results
    update_order_status(order) if any_updates
  rescue => e
    Rails.logger.error("Failed to update tracking for order #{order_id}: #{e.message}")
    raise e
  end

  private

  def update_tracking_status(tracking_event, scraper)
    Rails.logger.info("Fetching tracking from: #{tracking_event.tracking_url}")

    result = scraper.scrape(tracking_event.tracking_url, carrier: tracking_event.carrier)
    return false unless result

    # Update tracking event with scraped data
    tracking_event.update!(
      status: result[:status] || tracking_event.status,
      location: result[:location],
      event_timestamp: parse_timestamp(result[:last_update]) || tracking_event.event_timestamp,
      raw_data: result.to_json
    )

    Rails.logger.info("Updated tracking #{tracking_event.id}: #{result[:status]}")
    true
  rescue => e
    Rails.logger.error("Failed to update tracking event #{tracking_event.id}: #{e.message}")
    false
  end

  def update_order_status(order)
    # Get the most recent tracking status
    latest_event = order.tracking_events.order(event_timestamp: :desc).first
    return unless latest_event

    raw_data = parse_raw_data(latest_event.raw_data)
    normalized_status = raw_data["normalized_status"]&.to_sym

    new_status = case normalized_status
    when :delivered
      :delivered
    when :out_for_delivery, :in_transit
      :in_transit
    else
      order.status
    end

    if new_status != order.status.to_sym
      order.update!(status: new_status)
      Rails.logger.info("Updated order #{order.id} status to #{new_status}")
    end
  end

  def parse_timestamp(date_string)
    return nil if date_string.blank?
    Time.zone.parse(date_string)
  rescue ArgumentError
    nil
  end

  def parse_raw_data(json_string)
    return {} if json_string.blank?
    JSON.parse(json_string)
  rescue JSON::ParserError
    {}
  end
end
