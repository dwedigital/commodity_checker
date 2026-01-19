class LlmCommoditySuggester
  SYSTEM_PROMPT = <<~PROMPT
    You are an expert in UK/EU customs classification and the Harmonized System (HS) commodity codes.
    Your task is to suggest the most appropriate commodity code for products being imported.

    When given a product description, you should:
    1. Identify what the product is
    2. Determine the most likely HS code (typically 8-10 digits for UK)
    3. Explain your reasoning briefly

    Respond in JSON format only:
    {
      "commodity_code": "the 8-10 digit code",
      "confidence": 0.0 to 1.0,
      "reasoning": "brief explanation",
      "category": "general product category"
    }

    Common code prefixes:
    - 61/62: Clothing and apparel
    - 64: Footwear
    - 84: Machinery and mechanical appliances
    - 85: Electrical machinery, electronics
    - 94: Furniture
    - 95: Toys and games

    If you cannot determine a code with reasonable confidence, use confidence < 0.5 and suggest the most general applicable code.
  PROMPT

  def initialize
    @client = Anthropic::Client.new(api_key: api_key)
    @tariff_service = TariffLookupService.new
  end

  def suggest(product_description)
    return nil if product_description.blank?

    # First try the tariff API search
    api_suggestions = @tariff_service.search(product_description)

    # Use Claude to interpret and select the best code
    llm_response = query_claude(product_description, api_suggestions)

    return nil unless llm_response

    # Validate the suggested code exists
    validate_and_enrich(llm_response)
  rescue => e
    Rails.logger.error("LLM commodity suggestion failed: #{e.message}")
    nil
  end

  private

  def api_key
    Rails.application.credentials.dig(:anthropic, :api_key) ||
      ENV["ANTHROPIC_API_KEY"]
  end

  def query_claude(product_description, api_suggestions)
    context = build_context(product_description, api_suggestions)

    response = @client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 500,
      system: SYSTEM_PROMPT,
      messages: [
        { role: "user", content: context }
      ]
    )

    parse_llm_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("Claude API error: #{e.message}")
    nil
  end

  def build_context(product_description, api_suggestions)
    context = "Product to classify: #{product_description}\n\n"

    if api_suggestions.any?
      context += "Possible codes from UK Trade Tariff API:\n"
      api_suggestions.first(5).each do |s|
        context += "- #{s[:code]}: #{s[:description]}\n"
      end
      context += "\nSelect the most appropriate code from above, or suggest a better one if none fit well."
    else
      context += "No direct matches found in the tariff database. Please suggest the most appropriate code based on your knowledge."
    end

    context
  end

  def parse_llm_response(response)
    LlmResponseParser.extract_json_from_response(response)
  end

  def validate_and_enrich(suggestion)
    code = suggestion[:commodity_code]&.gsub(/[\s.-]/, "")
    return suggestion unless code

    # Try to validate the code exists in the tariff database
    commodity = @tariff_service.get_commodity(code)

    if commodity
      suggestion[:validated] = true
      suggestion[:official_description] = commodity[:description]
      suggestion[:duty_rate] = commodity[:duty_rate]
    else
      suggestion[:validated] = false
    end

    suggestion
  end
end
