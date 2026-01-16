# Finds detailed product information using web search (Tavily) and AI extraction
# Used only for email processing when product URLs are not available
class ProductInfoFinderService
  TAVILY_API_URL = "https://api.tavily.com/search".freeze

  EXTRACTION_PROMPT = <<~PROMPT
    You are an expert at extracting product information for customs classification.

    Given web search results about a product, extract detailed information that would help determine the correct commodity/tariff code.

    Respond with JSON only:
    {
      "found": true | false,
      "confidence": 0.0 to 1.0,
      "product_name": "full product name",
      "brand": "brand name",
      "category": "product category (e.g., Footwear, Clothing, Electronics)",
      "subcategory": "more specific category",
      "material": "primary material (e.g., leather, cotton, plastic)",
      "composition": "detailed material composition if available",
      "country_of_origin": "manufacturing country if mentioned",
      "description": "detailed product description for classification",
      "product_url": "URL to the product page if found",
      "image_url": "URL to a product image if found in the search results",
      "key_features": ["list", "of", "relevant", "features"]
    }

    Focus on details relevant for customs classification:
    - Material composition (leather, textile, rubber, plastic, etc.)
    - Product type and category
    - Whether it's for men/women/children
    - Any technical specifications

    If the search results don't contain the product or are unclear, set found=false.
  PROMPT

  def initialize
    @tavily_conn = Faraday.new do |f|
      f.options.timeout = 30
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    @anthropic = Anthropic::Client.new(api_key: anthropic_api_key)
  end

  # Find detailed product information
  # Returns hash with product details or nil if not found
  def find(product_name:, retailer: nil, brand: nil)
    return nil if product_name.blank?

    Rails.logger.info("ProductInfoFinderService: Searching for '#{product_name}' (retailer: #{retailer}, brand: #{brand})")

    # Build search query
    query = build_search_query(product_name, retailer, brand)

    # Search with Tavily
    search_results = search_tavily(query)
    return nil unless search_results&.any?

    # Use AI to extract product information from search results
    product_info = extract_product_info(product_name, retailer, search_results)

    if product_info && product_info[:found]
      Rails.logger.info("ProductInfoFinderService: Found product info with confidence #{product_info[:confidence]}")
      product_info
    else
      Rails.logger.info("ProductInfoFinderService: Could not find reliable product info")
      nil
    end
  rescue => e
    Rails.logger.error("ProductInfoFinderService error: #{e.message}")
    nil
  end

  # Build a description suitable for commodity code suggestion
  def build_description_for_classification(product_info)
    return nil unless product_info

    parts = []
    parts << product_info[:product_name] if product_info[:product_name].present?
    parts << "Brand: #{product_info[:brand]}" if product_info[:brand].present?
    parts << "Category: #{product_info[:category]}" if product_info[:category].present?
    parts << "Material: #{product_info[:material]}" if product_info[:material].present?
    parts << "Composition: #{product_info[:composition]}" if product_info[:composition].present?
    parts << product_info[:description] if product_info[:description].present?

    parts.join(". ")
  end

  private

  def tavily_api_key
    ENV["TAVILY_API_KEY"] || Rails.application.credentials.dig(:tavily, :api_key)
  end

  def anthropic_api_key
    Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
  end

  def build_search_query(product_name, retailer, brand)
    parts = [product_name]
    parts << brand if brand.present?
    parts << retailer if retailer.present?
    parts << "product details specifications"

    parts.join(" ")
  end

  def search_tavily(query)
    api_key = tavily_api_key
    unless api_key.present?
      Rails.logger.warn("ProductInfoFinderService: TAVILY_API_KEY not configured")
      return nil
    end

    response = @tavily_conn.post(TAVILY_API_URL) do |req|
      req.body = {
        api_key: api_key,
        query: query,
        search_depth: "advanced",        # More thorough search
        include_answer: false,           # We'll use our own AI
        include_raw_content: true,       # Get page content
        include_images: true,            # Get product images
        max_results: 5,                  # Limit results
        include_domains: [],             # No domain restrictions
        exclude_domains: []
      }
    end

    if response.success?
      results = response.body["results"]
      images = response.body["images"] || []
      Rails.logger.info("ProductInfoFinderService: Tavily returned #{results&.length || 0} results, #{images.length} images")

      # Store images separately for fallback
      @tavily_images = images
      results
    else
      Rails.logger.error("ProductInfoFinderService: Tavily error - #{response.status}: #{response.body}")
      nil
    end
  rescue Faraday::Error => e
    Rails.logger.error("ProductInfoFinderService: Tavily request failed - #{e.message}")
    nil
  end

  def extract_product_info(product_name, retailer, search_results)
    # Build context from search results
    context = build_extraction_context(product_name, retailer, search_results)

    response = @anthropic.messages.create(
      model: "claude-3-haiku-20240307",  # Fast and cheap
      max_tokens: 1000,
      system: EXTRACTION_PROMPT,
      messages: [
        { role: "user", content: context }
      ]
    )

    parse_extraction_response(response)
  rescue => e
    Rails.logger.error("ProductInfoFinderService: AI extraction failed - #{e.message}")
    nil
  end

  def build_extraction_context(product_name, retailer, search_results)
    context = "I'm looking for details about this product:\n"
    context += "Product: #{product_name}\n"
    context += "Retailer/Brand: #{retailer}\n\n" if retailer.present?
    context += "Here are the web search results:\n\n"

    search_results.each_with_index do |result, i|
      context += "--- Result #{i + 1} ---\n"
      context += "Title: #{result['title']}\n"
      context += "URL: #{result['url']}\n"
      context += "Content: #{truncate_content(result['content'] || result['raw_content'])}\n\n"
    end

    # Include images from Tavily if available
    if @tavily_images&.any?
      context += "--- Images Found ---\n"
      @tavily_images.first(5).each do |img|
        context += "Image URL: #{img}\n"
      end
      context += "\n"
    end

    context += "\nExtract the product information from these results. Include an image_url if you can identify a product image."
    context
  end

  def truncate_content(content)
    return "" if content.blank?
    content.to_s[0, 2000]  # Limit content length
  end

  def parse_extraction_response(response)
    content = response.content.first&.text
    return nil unless content

    # Extract JSON from response
    json_match = content.match(/\{.*\}/m)
    return nil unless json_match

    JSON.parse(json_match[0]).deep_symbolize_keys
  rescue JSON::ParserError => e
    Rails.logger.error("ProductInfoFinderService: Failed to parse AI response - #{e.message}")
    nil
  end
end
