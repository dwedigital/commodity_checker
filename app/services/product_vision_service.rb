class ProductVisionService
  SYSTEM_PROMPT = <<~PROMPT
    You are a product identification expert. Analyze the image and provide detailed information about the product shown.

    Your task is to identify:
    1. What the product is (be specific)
    2. The brand (if visible on the product or packaging)
    3. The material (if you can determine it from the appearance)
    4. The color and any patterns
    5. The category this product belongs to
    6. Any text, labels, or model numbers visible

    Respond in JSON format only:
    {
      "title": "concise product name",
      "description": "detailed description of the product including all visible features",
      "brand": "brand name if visible, otherwise null",
      "material": "material if determinable (e.g., cotton, leather, plastic, metal), otherwise null",
      "color": "primary color and any secondary colors or patterns",
      "category": "product category (e.g., Clothing, Footwear, Electronics, Home & Garden, Toys)",
      "visible_text": "any text, labels, or model numbers visible on the product",
      "confidence": 0.0 to 1.0 indicating how confident you are in the identification
    }

    Be thorough but concise. Focus on details that would help classify this product for customs/tariff purposes.
  PROMPT

  def initialize
    @client = Anthropic::Client.new(api_key: api_key)
  end

  def analyze(image_blob)
    return nil unless image_blob&.attached?

    image_data = encode_image(image_blob)
    return nil unless image_data

    response = query_claude_vision(image_data)
    return nil unless response

    parse_response(response)
  rescue => e
    Rails.logger.error("ProductVisionService error: #{e.message}")
    nil
  end

  def build_description(analysis_result)
    return nil unless analysis_result

    parts = []
    parts << analysis_result[:title] if analysis_result[:title].present?
    parts << analysis_result[:description] if analysis_result[:description].present?
    parts << "Brand: #{analysis_result[:brand]}" if analysis_result[:brand].present?
    parts << "Material: #{analysis_result[:material]}" if analysis_result[:material].present?
    parts << "Color: #{analysis_result[:color]}" if analysis_result[:color].present?
    parts << "Category: #{analysis_result[:category]}" if analysis_result[:category].present?

    parts.join(". ")
  end

  private

  def api_key
    Rails.application.credentials.dig(:anthropic, :api_key) ||
      ENV["ANTHROPIC_API_KEY"]
  end

  def encode_image(image_blob)
    # Download the blob and encode as base64
    image_blob.download do |file_data|
      return {
        data: Base64.strict_encode64(file_data),
        media_type: image_blob.content_type
      }
    end
  rescue => e
    Rails.logger.error("Failed to encode image: #{e.message}")
    nil
  end

  def query_claude_vision(image_data)
    response = @client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 1000,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: image_data[:media_type],
                data: image_data[:data]
              }
            },
            {
              type: "text",
              text: "Please analyze this product image and provide the details in JSON format."
            }
          ]
        }
      ]
    )

    response
  rescue Anthropic::Error => e
    Rails.logger.error("Claude Vision API error: #{e.message}")
    nil
  end

  def parse_response(response)
    LlmResponseParser.extract_json_from_response(response)
  end
end
