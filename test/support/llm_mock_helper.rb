# frozen_string_literal: true

require "minitest/mock" # Object#stub, used by stub_suggester

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
          model: "claude-sonnet-5",
          stop_reason: "end_turn"
        }.to_json
      )
  end

  # Load a fixture JSON file for LLM response
  def load_llm_fixture(name)
    path = Rails.root.join("test", "fixtures", "llm_responses", "#{name}.json")
    JSON.parse(File.read(path))
  end

  # A stand-in LlmCommoditySuggester that returns a canned suggestion for any
  # input. The real suggester is now the multi-call retrieve-then-walk pipeline
  # (Classification::*), which has its own tests. Layer tests (API, MCP,
  # extension) that only care about auth, metering and saving stub the suggester
  # at its .new seam instead of the raw Claude HTTP, mirroring the
  # LlmCommoditySuggester.stub(:new, ...) pattern in pages_controller_test.
  DEFAULT_SUGGESTION = {
    commodity_code: "6109100010",
    confidence: 0.85,
    reasoning: "Knitted cotton t-shirt",
    category: "Apparel",
    validated: true,
    official_description: "T-shirts, of cotton",
    duty_rate: "12%"
  }.freeze

  class FakeSuggester
    def initialize(result)
      @result = result
    end

    def suggest(_description)
      # A fresh mutable hash each call, like the real suggester (callers add
      # :product_lookup_id etc. to it).
      @result.dup
    end
  end

  # Runs the block with LlmCommoditySuggester.new returning a fake that yields
  # the given result (default DEFAULT_SUGGESTION) for any description.
  def stub_suggester(result = DEFAULT_SUGGESTION, &block)
    LlmCommoditySuggester.stub(:new, FakeSuggester.new(result), &block)
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
