class AnalyzeProductImageJob < ApplicationJob
  queue_as :default

  def perform(product_lookup_id)
    lookup = ProductLookup.find(product_lookup_id)

    unless lookup.photo? && lookup.product_image.attached?
      Rails.logger.error("AnalyzeProductImageJob: Lookup #{product_lookup_id} has no attached image")
      return
    end

    # Analyze the image with Claude Vision
    vision_service = ProductVisionService.new
    analysis = vision_service.analyze(lookup.product_image)

    if analysis
      # Build a description from the analysis
      description = vision_service.build_description(analysis)

      # Update lookup with image analysis results
      lookup.update!(
        title: analysis[:title],
        description: analysis[:description],
        brand: analysis[:brand],
        material: analysis[:material],
        category: analysis[:category],
        image_description: description,
        scrape_status: :completed,
        scraped_at: Time.current
      )

      # Get commodity code suggestion
      suggest_commodity_code(lookup, description)
    else
      # Analysis failed
      lookup.update!(
        scrape_status: :failed,
        scrape_error: "Could not analyze the image. Please try with a clearer photo.",
        scraped_at: Time.current
      )
    end

    # Broadcast update via Turbo Stream
    broadcast_update(lookup)
  rescue => e
    Rails.logger.error("AnalyzeProductImageJob failed for lookup #{product_lookup_id}: #{e.message}")
    ProductLookup.find(product_lookup_id).update!(
      scrape_status: :failed,
      scrape_error: "Analysis failed: #{e.message}",
      scraped_at: Time.current
    )
    broadcast_update(ProductLookup.find(product_lookup_id))
  end

  private

  def suggest_commodity_code(lookup, description)
    return if description.blank?

    suggester = LlmCommoditySuggester.new
    suggestion = suggester.suggest(description)

    if suggestion && suggestion[:commodity_code].present?
      lookup.update!(
        suggested_commodity_code: suggestion[:commodity_code],
        commodity_code_confidence: suggestion[:confidence],
        llm_reasoning: build_reasoning(suggestion)
      )

      Rails.logger.info("Suggested #{suggestion[:commodity_code]} for photo lookup #{lookup.id} (confidence: #{suggestion[:confidence]})")
    else
      Rails.logger.warn("Could not suggest commodity code for photo lookup #{lookup.id}")
    end
  rescue => e
    Rails.logger.error("Failed to suggest code for photo lookup #{lookup.id}: #{e.message}")
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
    Turbo::StreamsChannel.broadcast_replace_to(
      "product_lookup_#{lookup.id}",
      target: "product_lookup_#{lookup.id}",
      partial: "product_lookups/product_lookup",
      locals: { product_lookup: lookup }
    )
  rescue => e
    Rails.logger.warn("Failed to broadcast update for photo lookup #{lookup.id}: #{e.message}")
  end
end
