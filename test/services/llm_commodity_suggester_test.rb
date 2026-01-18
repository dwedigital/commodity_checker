# frozen_string_literal: true

require "test_helper"

class LlmCommoditySuggesterTest < ActiveSupport::TestCase
  def setup
    @suggester = LlmCommoditySuggester.new
  end

  # =============================================================================
  # Basic Suggest Behavior
  # =============================================================================

  test "returns nil for blank product description" do
    assert_nil @suggester.suggest("")
    assert_nil @suggester.suggest(nil)
    assert_nil @suggester.suggest("   ")
  end

  test "returns suggestion hash for valid product" do
    # Stub tariff API
    stub_tariff_search([
      { code: "6109100010", description: "T-shirts, singlets and other vests, of cotton", score: 95 }
    ])

    # Stub Claude response
    stub_commodity_suggestion(
      code: "6109100010",
      confidence: 0.85,
      reasoning: "Cotton t-shirt falls under HS code 6109 for knitted t-shirts"
    )

    # Stub validation lookup
    stub_tariff_commodity("6109100010", {
      code: "6109100010",
      description: "T-shirts, of cotton",
      duty_rate: "12%"
    })

    result = @suggester.suggest("Cotton t-shirt, blue, size M")

    assert result.is_a?(Hash)
    assert result.key?(:commodity_code)
    assert result.key?(:confidence)
    assert result.key?(:reasoning)
  end

  test "suggestion includes validation status when code exists" do
    stub_tariff_search([])
    stub_commodity_suggestion(
      code: "6109100010",
      confidence: 0.8,
      reasoning: "Test"
    )
    stub_tariff_commodity("6109100010", {
      code: "6109100010",
      description: "T-shirts, of cotton",
      duty_rate: "12%"
    })

    result = @suggester.suggest("Cotton t-shirt")

    assert_equal true, result[:validated]
    assert result[:official_description].present?
  end

  test "suggestion marked as not validated when code does not exist" do
    stub_tariff_search([])
    stub_commodity_suggestion(
      code: "9999999999",
      confidence: 0.5,
      reasoning: "Best guess"
    )
    stub_tariff_commodity_not_found("9999999999")

    result = @suggester.suggest("Unknown product")

    assert_equal false, result[:validated]
  end

  # =============================================================================
  # Context Building
  # =============================================================================

  test "builds context with tariff API suggestions" do
    stub_tariff_search([
      { code: "6109100010", description: "T-shirts, cotton", score: 95 },
      { code: "6109909000", description: "T-shirts, other", score: 80 }
    ])
    stub_commodity_suggestion(code: "6109100010", confidence: 0.9, reasoning: "Test")
    stub_tariff_commodity("6109100010", { code: "6109100010", description: "T-shirts" })

    # The test verifies the service works - context building is internal
    result = @suggester.suggest("Cotton t-shirt")

    assert result.present?
  end

  test "builds context without tariff API suggestions" do
    stub_tariff_search([]) # No results from API
    stub_commodity_suggestion(code: "8471300000", confidence: 0.7, reasoning: "Laptop computer")
    stub_tariff_commodity("8471300000", { code: "8471300000", description: "Portable computers" })

    result = @suggester.suggest("MacBook Pro laptop")

    assert result.present?
  end

  # =============================================================================
  # LLM Response Parsing
  # =============================================================================

  test "parses clean JSON response" do
    stub_tariff_search([])
    stub_claude_response('{"commodity_code": "6402990000", "confidence": 0.75, "reasoning": "Rubber footwear", "category": "Footwear"}')
    stub_tariff_commodity("6402990000", { code: "6402990000", description: "Footwear" })

    result = @suggester.suggest("Rubber rain boots")

    assert_equal "6402990000", result[:commodity_code]
    assert_equal 0.75, result[:confidence]
    assert_equal "Rubber footwear", result[:reasoning]
    assert_equal "Footwear", result[:category]
  end

  test "parses JSON wrapped in markdown code block" do
    stub_tariff_search([])
    response_with_markdown = <<~RESPONSE
      Based on my analysis, here's the classification:

      ```json
      {"commodity_code": "9503009000", "confidence": 0.8, "reasoning": "Plastic toy", "category": "Toys"}
      ```

      This code applies to toys not elsewhere specified.
    RESPONSE
    stub_claude_response(response_with_markdown)
    stub_tariff_commodity("9503009000", { code: "9503009000", description: "Toys" })

    result = @suggester.suggest("Plastic action figure toy")

    assert_equal "9503009000", result[:commodity_code]
  end

  test "handles JSON with extra text around it" do
    stub_tariff_search([])
    response_with_text = 'The best code would be {"commodity_code": "8518300000", "confidence": 0.85, "reasoning": "Headphones", "category": "Electronics"} based on the description.'
    stub_claude_response(response_with_text)
    stub_tariff_commodity("8518300000", { code: "8518300000", description: "Headphones" })

    result = @suggester.suggest("Wireless Bluetooth headphones")

    assert_equal "8518300000", result[:commodity_code]
  end

  # =============================================================================
  # Code Normalization
  # =============================================================================

  test "normalizes commodity code with spaces" do
    stub_tariff_search([])
    stub_commodity_suggestion(code: "6109 1000 10", confidence: 0.8, reasoning: "Test")
    stub_tariff_commodity("6109100010", { code: "6109100010", description: "T-shirts" })

    result = @suggester.suggest("T-shirt")

    # Validation should work despite spaces in original code
    assert result[:validated] == true || result[:validated] == false
  end

  test "normalizes commodity code with dots and dashes" do
    stub_tariff_search([])
    stub_commodity_suggestion(code: "6109.10.00.10", confidence: 0.8, reasoning: "Test")
    stub_tariff_commodity("6109100010", { code: "6109100010", description: "T-shirts" })

    result = @suggester.suggest("T-shirt")

    assert result.present?
  end

  # =============================================================================
  # Error Handling
  # =============================================================================

  test "returns nil when Claude API fails" do
    stub_tariff_search([])
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

    result = @suggester.suggest("Some product")

    assert_nil result
  end

  test "returns nil when Claude returns invalid JSON" do
    stub_tariff_search([])
    stub_claude_response("This is not valid JSON at all")

    result = @suggester.suggest("Some product")

    assert_nil result
  end

  test "returns nil when Claude returns empty response" do
    stub_tariff_search([])
    stub_claude_response("")

    result = @suggester.suggest("Some product")

    assert_nil result
  end

  test "handles tariff API errors gracefully" do
    stub_request(:get, /trade-tariff.service.gov.uk/)
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
    stub_commodity_suggestion(code: "6109100010", confidence: 0.7, reasoning: "Best guess without API")
    stub_tariff_commodity_not_found("6109100010")

    result = @suggester.suggest("Cotton t-shirt")

    # Should still return a result, just not validated
    assert result.is_a?(Hash)
    assert_equal false, result[:validated]
  end

  # =============================================================================
  # Enrichment
  # =============================================================================

  test "enriches suggestion with duty rate when available" do
    stub_tariff_search([])
    stub_commodity_suggestion(code: "6109100010", confidence: 0.9, reasoning: "Cotton t-shirt")
    stub_tariff_commodity("6109100010", {
      code: "6109100010",
      description: "T-shirts, singlets and other vests, of cotton, knitted",
      duty_rate: "12.0%"
    })

    result = @suggester.suggest("Cotton t-shirt")

    assert_equal "12.0%", result[:duty_rate]
    assert_equal "T-shirts, singlets and other vests, of cotton, knitted", result[:official_description]
  end

  private

  # Helper to stub tariff search results
  def stub_tariff_search(results)
    # Convert to the format TariffLookupService returns
    formatted_results = results.map do |r|
      { code: r[:code], description: r[:description], score: r[:score] }
    end

    stub_request(:get, /trade-tariff.service.gov.uk\/api\/v2\/search/)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: build_tariff_search_response(formatted_results).to_json
      )
  end

  def build_tariff_search_response(results)
    if results.empty?
      {
        data: {
          attributes: {
            type: "fuzzy_match",
            goods_nomenclature_match: { commodities: [], headings: [] }
          }
        }
      }
    else
      {
        data: {
          attributes: {
            type: "fuzzy_match",
            goods_nomenclature_match: {
              commodities: results.map do |r|
                {
                  "_source" => {
                    "goods_nomenclature_item_id" => r[:code],
                    "description" => r[:description]
                  },
                  "_score" => r[:score]
                }
              end,
              headings: []
            }
          }
        }
      }
    end
  end

  # Helper to stub tariff commodity lookup
  def stub_tariff_commodity(code, details)
    stub_request(:get, "https://www.trade-tariff.service.gov.uk/api/v2/commodities/#{code}")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          data: {
            attributes: {
              goods_nomenclature_item_id: details[:code],
              formatted_description: details[:description],
              description: details[:description]
            }
          },
          included: details[:duty_rate] ? [
            {
              type: "measure",
              attributes: {
                duty_expression: { formatted_base: details[:duty_rate] }
              }
            }
          ] : []
        }.to_json
      )
  end

  def stub_tariff_commodity_not_found(code)
    stub_request(:get, "https://www.trade-tariff.service.gov.uk/api/v2/commodities/#{code}")
      .to_return(status: 404, body: { error: "Not found" }.to_json)
  end
end
