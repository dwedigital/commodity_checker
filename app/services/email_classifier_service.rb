class EmailClassifierService
  SYSTEM_PROMPT = <<~PROMPT
    You are an expert at analyzing e-commerce emails. Your task is to classify emails and extract product information.

    Analyze the email and respond with JSON only:
    {
      "email_type": "order_confirmation" | "shipping_notification" | "delivery_confirmation" | "return_confirmation" | "marketing" | "other",
      "confidence": 0.0 to 1.0,
      "contains_products": true | false,
      "products": [
        {
          "name": "product name",
          "brand": "brand if mentioned",
          "color": "color if mentioned",
          "size": "size if mentioned",
          "material": "material if mentioned",
          "quantity": 1
        }
      ],
      "retailer": "retailer/store name",
      "order_reference": "order number if present",
      "reasoning": "brief explanation of classification"
    }

    Email types:
    - order_confirmation: Confirms a purchase was made, lists what was ordered
    - shipping_notification: Package has shipped, includes tracking info, may not list products
    - delivery_confirmation: Package was delivered
    - return_confirmation: Return/refund processed
    - marketing: Promotional emails, newsletters
    - other: Doesn't fit above categories

    Rules:
    - Only set contains_products=true if specific product names are mentioned
    - Extract actual product names, not generic text like "your items" or "your order"
    - If it's a shipping notification without product details, contains_products should be false
    - Include color, size, material only if explicitly stated
  PROMPT

  def initialize
    @client = Anthropic::Client.new(api_key: api_key)
  end

  # Classify email and extract structured data
  # Returns hash with email_type, products, etc.
  def classify(email_subject:, email_body:, from_address: nil)
    return default_response("Email content is blank") if email_body.blank?

    response = query_claude(email_subject, email_body, from_address)
    return default_response("Failed to classify email") unless response

    # Ensure we have the expected structure
    normalize_response(response)
  rescue => e
    Rails.logger.error("EmailClassifierService error: #{e.message}")
    default_response("Classification failed: #{e.message}")
  end

  # Quick check if email likely contains products worth processing
  def should_process_for_products?(email_subject:, email_body:, from_address: nil)
    result = classify(
      email_subject: email_subject,
      email_body: email_body,
      from_address: from_address
    )

    # Only process if it's an order confirmation with products
    result[:email_type] == "order_confirmation" &&
      result[:contains_products] == true &&
      result[:products].any? &&
      result[:confidence] >= 0.6
  end

  private

  def api_key
    Rails.application.credentials.dig(:anthropic, :api_key) ||
      ENV["ANTHROPIC_API_KEY"]
  end

  def query_claude(subject, body, from_address)
    # Truncate body to avoid token limits (keep first ~4000 chars)
    truncated_body = body.to_s[0, 4000]

    user_content = build_prompt(subject, truncated_body, from_address)

    response = @client.messages.create(
      model: "claude-3-haiku-20240307",  # Fast and cheap for classification
      max_tokens: 1000,
      system: SYSTEM_PROMPT,
      messages: [
        { role: "user", content: user_content }
      ]
    )

    parse_response(response)
  rescue Faraday::Error, StandardError => e
    Rails.logger.error("Claude API error in EmailClassifierService: #{e.message}")
    nil
  end

  def build_prompt(subject, body, from_address)
    prompt = "Analyze this email:\n\n"
    prompt += "From: #{from_address}\n" if from_address.present?
    prompt += "Subject: #{subject}\n\n" if subject.present?
    prompt += "Body:\n#{body}"
    prompt
  end

  def parse_response(response)
    content = response.content.first&.text
    return nil unless content

    # Extract JSON from response (handle markdown code blocks)
    json_match = content.match(/\{.*\}/m)
    return nil unless json_match

    JSON.parse(json_match[0]).deep_symbolize_keys
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse classifier response: #{e.message}")
    nil
  end

  def normalize_response(response)
    {
      email_type: response[:email_type] || "other",
      confidence: response[:confidence] || 0.0,
      contains_products: response[:contains_products] || false,
      products: normalize_products(response[:products]),
      retailer: response[:retailer],
      order_reference: response[:order_reference],
      reasoning: response[:reasoning]
    }
  end

  def normalize_products(products)
    return [] unless products.is_a?(Array)

    products.map do |p|
      next unless p.is_a?(Hash)

      {
        name: p[:name],
        brand: p[:brand],
        color: p[:color],
        size: p[:size],
        material: p[:material],
        quantity: p[:quantity] || 1
      }
    end.compact
  end

  def default_response(reasoning)
    {
      email_type: "other",
      confidence: 0.0,
      contains_products: false,
      products: [],
      retailer: nil,
      order_reference: nil,
      reasoning: reasoning
    }
  end
end
