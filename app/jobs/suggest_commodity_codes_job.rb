class SuggestCommodityCodesJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.includes(:order_items, :user).find(order_id)
    suggester = LlmCommoditySuggester.new

    order.order_items.where(suggested_commodity_code: nil).each do |item|
      suggest_code_for_item(item, suggester, order.user)

      # Small delay between API calls to avoid rate limiting
      sleep(0.5)
    end
  rescue => e
    Rails.logger.error("Failed to suggest commodity codes for order #{order_id}: #{e.message}")
    raise e
  end

  private

  def suggest_code_for_item(item, suggester, user)
    description = item.enhanced_description
    Rails.logger.info("Suggesting commodity code for: #{description}")

    suggestion = suggester.suggest(description)

    if suggestion && suggestion[:commodity_code].present?
      item.update!(
        suggested_commodity_code: suggestion[:commodity_code],
        commodity_code_confidence: suggestion[:confidence],
        llm_reasoning: CommoditySuggestionFormatter.build_reasoning(suggestion)
      )

      # Track commodity code suggestion
      track_analytics(user, "commodity_code_suggested",
        order_item_id: item.id,
        commodity_code: suggestion[:commodity_code],
        confidence: suggestion[:confidence]
      )

      Rails.logger.info("Suggested #{suggestion[:commodity_code]} for '#{item.description}' (confidence: #{suggestion[:confidence]})")
    else
      Rails.logger.warn("Could not suggest commodity code for: #{item.description}")
    end
  rescue => e
    Rails.logger.error("Failed to suggest code for item #{item.id}: #{e.message}")
  end

  def track_analytics(user, event_name, properties = {})
    AnalyticsTracker.new(user: user).track(event_name, properties)
  rescue => e
    Rails.logger.error("Analytics tracking failed: #{e.message}")
  end
end
