class ScrapeProductPageJob < ApplicationJob
  queue_as :default

  def perform(product_lookup_id: nil, order_item_id: nil)
    if product_lookup_id
      process_product_lookup(product_lookup_id)
    elsif order_item_id
      process_order_item(order_item_id)
    else
      Rails.logger.error("ScrapeProductPageJob called without product_lookup_id or order_item_id")
    end
  end

  private

  def process_product_lookup(product_lookup_id)
    lookup = ProductLookup.find(product_lookup_id)

    # Scrape the product page
    scraper = ProductScraperService.new
    result = scraper.scrape(lookup.url)

    # Update lookup with scraped data
    update_lookup_from_result(lookup, result)

    # Get commodity code suggestion if scraping was at least partially successful
    if lookup.completed? || lookup.partial?
      suggest_commodity_code_for_lookup(lookup)
    end

    # Broadcast update via Turbo Stream
    broadcast_update(lookup)
  rescue => e
    Rails.logger.error("Failed to scrape product page for lookup #{product_lookup_id}: #{e.message}")
    ProductLookup.find(product_lookup_id).update!(
      scrape_status: :failed,
      scrape_error: e.message,
      scraped_at: Time.current
    )
  end

  def process_order_item(order_item_id)
    item = OrderItem.find(order_item_id)
    return unless item.product_url.present?

    # Scrape the product page
    scraper = ProductScraperService.new
    result = scraper.scrape(item.product_url)

    # Build enhanced description from scraped data
    if result[:status] == :completed || result[:status] == :partial
      enhanced = build_enhanced_description(result)

      if enhanced.present? && enhanced != item.description
        item.update!(scraped_description: enhanced)

        # Re-run commodity code suggestion with enhanced description
        suggester = LlmCommoditySuggester.new
        suggestion = suggester.suggest(enhanced)

        if suggestion && suggestion[:commodity_code].present?
          item.update!(
            suggested_commodity_code: suggestion[:commodity_code],
            commodity_code_confidence: suggestion[:confidence],
            llm_reasoning: build_reasoning(suggestion)
          )
        end
      end
    end
  rescue => e
    Rails.logger.error("Failed to scrape product page for order item #{order_item_id}: #{e.message}")
  end

  def update_lookup_from_result(lookup, result)
    lookup.update!(
      title: result[:title],
      description: result[:description],
      brand: result[:brand],
      category: result[:category],
      price: result[:price],
      currency: result[:currency],
      material: result[:material],
      image_url: result[:image_url],
      structured_data: result[:structured_data],
      retailer_name: result[:retailer_name] || lookup.retailer_name,
      scrape_status: result[:status],
      scrape_error: result[:error],
      scraped_at: result[:scraped_at] || Time.current
    )
  end

  def suggest_commodity_code_for_lookup(lookup)
    description = lookup.display_description
    return if description.blank?

    suggester = LlmCommoditySuggester.new
    suggestion = suggester.suggest(description)

    if suggestion && suggestion[:commodity_code].present?
      lookup.update!(
        suggested_commodity_code: suggestion[:commodity_code],
        commodity_code_confidence: suggestion[:confidence],
        llm_reasoning: build_reasoning(suggestion)
      )

      Rails.logger.info("Suggested #{suggestion[:commodity_code]} for product lookup #{lookup.id} (confidence: #{suggestion[:confidence]})")
    else
      Rails.logger.warn("Could not suggest commodity code for product lookup #{lookup.id}")
    end
  rescue => e
    Rails.logger.error("Failed to suggest code for product lookup #{lookup.id}: #{e.message}")
  end

  def build_enhanced_description(result)
    parts = []
    parts << result[:title] if result[:title].present?
    parts << result[:description] if result[:description].present?
    parts << "Brand: #{result[:brand]}" if result[:brand].present?
    parts << "Category: #{result[:category]}" if result[:category].present?
    parts << "Material: #{result[:material]}" if result[:material].present?

    parts.join(". ")
  end

  def build_reasoning(suggestion)
    parts = []
    parts << suggestion[:reasoning] if suggestion[:reasoning].present?
    parts << "Category: #{suggestion[:category]}" if suggestion[:category].present?
    parts << "Official: #{suggestion[:official_description]}" if suggestion[:official_description].present?
    parts << "(Validated)" if suggestion[:validated]
    parts << "(Unvalidated - code may need verification)" if suggestion[:validated] == false

    parts.join(" | ")
  end

  def broadcast_update(lookup)
    # Turbo Stream broadcast for live updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "product_lookup_#{lookup.id}",
      target: "product_lookup_#{lookup.id}",
      partial: "product_lookups/product_lookup",
      locals: { product_lookup: lookup }
    )
  rescue => e
    # Don't fail the job if broadcast fails
    Rails.logger.warn("Failed to broadcast update for lookup #{lookup.id}: #{e.message}")
  end
end
