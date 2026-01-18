# frozen_string_literal: true

# Helper for mocking LLM (Claude) API responses in tests
# Use this instead of VCR for Anthropic API calls since LLM outputs are non-deterministic
module LlmMockHelper
  # Stub Claude API to return a specific response
  def stub_claude_response(response_body)
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "msg_test_123",
          type: "message",
          role: "assistant",
          content: [ { type: "text", text: response_body } ],
          model: "claude-sonnet-4-20250514",
          stop_reason: "end_turn"
        }.to_json
      )
  end

  # Load a fixture JSON file for LLM response
  def load_llm_fixture(name)
    path = Rails.root.join("test", "fixtures", "llm_responses", "#{name}.json")
    JSON.parse(File.read(path))
  end

  # Stub Claude to return a commodity suggestion response
  def stub_commodity_suggestion(code:, confidence:, reasoning:)
    response = {
      commodity_code: code,
      confidence: confidence,
      reasoning: reasoning,
      category: "Test Category"
    }.to_json
    stub_claude_response(response)
  end

  # Stub Claude to return an email classification response
  def stub_email_classification(type:, confidence: 0.9, products: [])
    response = {
      email_type: type,
      confidence: confidence,
      contains_products: products.any?,
      products: products,
      retailer: "Test Retailer",
      reasoning: "Test classification"
    }.to_json
    stub_claude_response(response)
  end
end
