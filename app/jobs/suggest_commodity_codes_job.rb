class SuggestCommodityCodesJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.includes(:order_items).find(order_id)
    suggester = LlmCommoditySuggester.new

    order.order_items.where(suggested_commodity_code: nil).each do |item|
      suggest_code_for_item(item, suggester)

      # Small delay between API calls to avoid rate limiting
      sleep(0.5)
    end
  rescue => e
    Rails.logger.error("Failed to suggest commodity codes for order #{order_id}: #{e.message}")
    raise e
  end

  private

  def suggest_code_for_item(item, suggester)
    Rails.logger.info("Suggesting commodity code for: #{item.description}")

    suggestion = suggester.suggest(item.description)

    if suggestion && suggestion[:commodity_code].present?
      item.update!(
        suggested_commodity_code: suggestion[:commodity_code],
        commodity_code_confidence: suggestion[:confidence],
        llm_reasoning: build_reasoning(suggestion)
      )

      Rails.logger.info("Suggested #{suggestion[:commodity_code]} for '#{item.description}' (confidence: #{suggestion[:confidence]})")
    else
      Rails.logger.warn("Could not suggest commodity code for: #{item.description}")
    end
  rescue => e
    Rails.logger.error("Failed to suggest code for item #{item.id}: #{e.message}")
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
end
