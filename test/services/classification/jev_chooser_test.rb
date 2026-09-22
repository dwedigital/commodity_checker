# frozen_string_literal: true

require "test_helper"

class JevChooserTest < ActiveSupport::TestCase
  # A fake JevClient: records each call and returns a canned response.
  class FakeClient
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def evaluate(state:, questions:)
      @calls << { state: state, questions: questions }
      @response
    end
  end

  # A fake fallback chooser used to prove numeric delegation.
  class FakeFallback
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = []
    end

    def choose(question:, options:, context:)
      @calls << { question: question, options: options, context: context }
      @result
    end
  end

  def jev_response(choice: "6109", confidence: 0.9, probabilities: { "6109" => 0.9 })
    {
      "model" => "jev-1.13.0",
      "answers" => {
        Classification::JevChooser::QUESTION_KEY => {
          "type" => "choice",
          "choice" => choice,
          "confidence" => confidence,
          "probabilities" => probabilities
        }
      },
      "usage" => { "input_tokens" => 120 }
    }
  end

  def heading_options
    [
      { key: "6109", label: "T-shirts, singlets and other vests, knitted or crocheted" },
      { key: "6110", label: "Jerseys, pullovers, cardigans, knitted or crocheted" }
    ]
  end

  def context
    { product: "a knitted cotton t-shirt", path: [ "Chapter 61" ], level: :heading }
  end

  # ---------------------------------------------------------------------------
  # response mapping
  # ---------------------------------------------------------------------------

  test "choose maps the Jev answer onto the chooser contract" do
    client = FakeClient.new(jev_response(choice: "6109", confidence: 0.87, probabilities: { "6109" => 0.87, "6110" => 0.13 }))
    chooser = Classification::JevChooser.new(client: client)

    result = chooser.choose(question: "Which heading?", options: heading_options, context: context)

    assert_equal "6109", result[:key]
    assert_in_delta 0.87, result[:confidence], 0.0001
    assert_equal({ "6109" => 0.87, "6110" => 0.13 }, result[:probabilities])
    assert_equal "jev", result[:chooser]
    assert_equal "jev p=0.87", result[:reasoning]
  end

  test "choose sends product, classified_so_far and criteria of option labels" do
    client = FakeClient.new(jev_response)
    chooser = Classification::JevChooser.new(client: client)

    chooser.choose(
      question: "Which heading?",
      options: heading_options,
      context: { product: "a knitted cotton t-shirt", path: [ "Section XI", "Chapter 61" ], level: :heading }
    )

    call = client.calls.first
    assert_equal "a knitted cotton t-shirt", call[:state][:product]
    assert_equal "Section XI > Chapter 61", call[:state][:classified_so_far]

    question = call[:questions][Classification::JevChooser::QUESTION_KEY]
    assert_equal "choice", question[:type]
    assert_equal "Which heading?", question[:instructions]
    assert_equal(
      {
        "6109" => "T-shirts, singlets and other vests, knitted or crocheted",
        "6110" => "Jerseys, pullovers, cardigans, knitted or crocheted"
      },
      question[:criteria]
    )
  end

  test "choose suffixes duplicate labels with the option key to keep criteria unique" do
    client = FakeClient.new(jev_response(choice: "6109_a"))
    chooser = Classification::JevChooser.new(client: client)
    options = [
      { key: "6109_a", label: "T-shirts" },
      { key: "6109_b", label: "T-shirts" }
    ]

    chooser.choose(question: "?", options: options, context: context)

    criteria = client.calls.first[:questions][Classification::JevChooser::QUESTION_KEY][:criteria]
    assert_equal "T-shirts (6109_a)", criteria["6109_a"]
    assert_equal "T-shirts (6109_b)", criteria["6109_b"]
  end

  test "choose uses the option key as the label when a label is blank" do
    client = FakeClient.new(jev_response(choice: "6109"))
    chooser = Classification::JevChooser.new(client: client)
    options = [
      { key: "6109", label: "" },
      { key: "6110", label: "Jerseys" }
    ]

    chooser.choose(question: "?", options: options, context: context)

    criteria = client.calls.first[:questions][Classification::JevChooser::QUESTION_KEY][:criteria]
    assert_equal "6109", criteria["6109"]
    assert_equal "Jerseys", criteria["6110"]
  end

  test "choose returns nil when the client fails" do
    client = FakeClient.new(nil)
    chooser = Classification::JevChooser.new(client: client)

    assert_nil chooser.choose(question: "?", options: heading_options, context: context)
  end

  test "choose returns nil without calling the client for more than 255 options" do
    client = FakeClient.new(jev_response)
    chooser = Classification::JevChooser.new(client: client)
    options = (1..256).map { |i| { key: "k#{i}", label: "Option number #{i}" } }

    assert_nil chooser.choose(question: "?", options: options, context: context)
    assert_empty client.calls
  end

  test "choose returns nil for empty options" do
    client = FakeClient.new(jev_response)
    chooser = Classification::JevChooser.new(client: client)

    assert_nil chooser.choose(question: "?", options: [], context: context)
    assert_empty client.calls
  end

  # ---------------------------------------------------------------------------
  # numeric routing
  # ---------------------------------------------------------------------------

  def numeric_options
    [
      { key: "5208", label: "Weighing not more than 200 g/m2" },
      { key: "5209", label: "Weighing more than 200 g/m2" }
    ]
  end

  test "choose delegates numeric-threshold levels to the fallback and tags the result" do
    client = FakeClient.new(jev_response)
    fallback = FakeFallback.new({ key: "5209", confidence: 0.7, probabilities: { "5209" => 0.7 }, reasoning: "claude reasoning", chooser: "claude" })
    chooser = Classification::JevChooser.new(client: client, fallback: fallback)

    result = chooser.choose(question: "Which weight band?", options: numeric_options, context: context)

    assert_equal "5209", result[:key]
    assert_equal "claude(numeric)", result[:chooser]
    assert_equal "claude reasoning", result[:reasoning]
    assert_empty client.calls, "Jev should be skipped on a numeric level when a fallback exists"
    assert_equal 1, fallback.calls.size
  end

  test "choose returns nil when the numeric fallback fails" do
    client = FakeClient.new(jev_response)
    fallback = FakeFallback.new(nil)
    chooser = Classification::JevChooser.new(client: client, fallback: fallback)

    assert_nil chooser.choose(question: "?", options: numeric_options, context: context)
    assert_empty client.calls
  end

  test "choose without a fallback still asks Jev on numeric levels but flags the caveat" do
    client = FakeClient.new(jev_response(choice: "5209", confidence: 0.55, probabilities: { "5209" => 0.55, "5208" => 0.45 }))
    chooser = Classification::JevChooser.new(client: client)

    result = chooser.choose(question: "?", options: numeric_options, context: context)

    assert_equal "5209", result[:key]
    assert_equal "jev", result[:chooser]
    assert_equal 1, client.calls.size
    assert_match(/numeric/i, result[:reasoning])
  end

  # ---------------------------------------------------------------------------
  # numeric_level?
  # ---------------------------------------------------------------------------

  test "numeric_level? detects thresholds, units, percentages and comparisons" do
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Weighing not more than 100 g/m2" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Of a power exceeding 750 W" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Of a capacity not exceeding 50 litres" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Containing 85% or more by weight of cotton" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Less than 3 mm thick" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Screen diagonal ≤ 55 cm" } ])
    assert Classification::JevChooser.numeric_level?([ { key: "a", label: "Diagonal > 45 cm" } ])
  end

  test "numeric_level? is false for plain labels, path separators and bare code digits" do
    refute Classification::JevChooser.numeric_level?([ { key: "6109100010", label: "Of cotton > T-shirts" } ])
    refute Classification::JevChooser.numeric_level?([ { key: "6109902000", label: "6109902000 Of man-made fibres" } ])
    refute Classification::JevChooser.numeric_level?([ { key: "a", label: "Jerseys, pullovers and cardigans, knitted or crocheted" } ])
    refute Classification::JevChooser.numeric_level?([ { key: "a", label: "Babies' garments and clothing accessories" } ])
  end
end
