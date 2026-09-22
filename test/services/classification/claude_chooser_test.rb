# frozen_string_literal: true

require "test_helper"

module Classification
  class ClaudeChooserTest < ActiveSupport::TestCase
    def setup
      @chooser = ClaudeChooser.new
      @options = [ { key: "6109", label: "T-shirts, knitted" }, { key: "6110", label: "Jerseys, knitted" } ]
      @context = { product: "a knitted cotton t-shirt", path: [], level: :heading, chapter_note: nil }
    end

    test "the JSON schema enum contains exactly the offered option keys" do
      schema = @chooser.send(:schema_for, %w[6109 6110 6111])

      assert_equal %w[6109 6110 6111], schema.dig(:properties, :key, :enum)
    end

    test "returns the chosen key with confidence and probabilities" do
      stub_claude_response('{"key":"6109","confidence":0.88,"reasoning":"knitted t-shirt"}')

      result = @chooser.choose(question: "Which heading?", options: @options, context: @context)

      assert_equal "6109", result[:key]
      assert_in_delta 0.88, result[:confidence], 0.0001
      assert_equal "claude", result[:chooser]
      assert_equal({ "6109" => 0.88, "6110" => 0.0 }, result[:probabilities])
    end

    test "returns nil when the model returns a key that was not offered" do
      stub_claude_response('{"key":"9999","confidence":0.9,"reasoning":"off-list"}')

      assert_nil @chooser.choose(question: "Which heading?", options: @options, context: @context)
    end

    test "returns nil on an API error" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_raise(Faraday::ConnectionFailed.new("refused"))

      assert_nil @chooser.choose(question: "Which heading?", options: @options, context: @context)
    end

    test "returns nil for an empty option set without calling the API" do
      assert_nil @chooser.choose(question: "Which heading?", options: [], context: @context)
    end
  end
end
