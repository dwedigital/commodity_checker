# frozen_string_literal: true

require "test_helper"

# Contract tests for the public LlmCommoditySuggester surface. The internals are
# now the retrieve-then-walk pipeline (Classification::*), tested in detail under
# test/services/classification/. Here we pin the contract every caller relies on:
# blank -> nil, a hash carrying the expected keys, validated true/false, and nil
# on failure. Claude is faked (analyzer + chooser); the tariff API is stubbed.
class LlmCommoditySuggesterTest < ActiveSupport::TestCase
  API = "https://www.trade-tariff.service.gov.uk/api/v2"

  # Returns a fixed analysis, standing in for the one Claude analyzer call.
  class FakeAnalyzer
    def initialize(result) = (@result = result)
    def analyze(_description) = @result
  end

  # Picks the first option at every step, so the walk is deterministic.
  class FirstChooser < Classification::Chooser
    def choose(question:, options:, context:)
      key = options.first[:key]
      { key: key, confidence: 0.9, probabilities: { key => 0.9 }, reasoning: "first", chooser: "fake" }
    end
  end

  ANALYSIS = {
    product_summary: "A knitted cotton t-shirt",
    search_phrases: [ "knitted cotton t-shirt" ],
    attributes: { material: "cotton", construction: "knitted" },
    numeric_facts: [ "100% cotton" ],
    candidate_chapters: [ "61" ]
  }.freeze

  # ---------------------------------------------------------------------------
  # Blank input
  # ---------------------------------------------------------------------------

  test "returns nil for blank product description" do
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(ANALYSIS.dup), chooser: FirstChooser.new)

    assert_nil suggester.suggest("")
    assert_nil suggester.suggest(nil)
    assert_nil suggester.suggest("   ")
  end

  # ---------------------------------------------------------------------------
  # Successful pipeline run (real retriever + walker + tree over stubbed HTTP)
  # ---------------------------------------------------------------------------

  test "returns a suggestion hash carrying every contract key" do
    stub_full_tariff(validated: true)
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(ANALYSIS.dup), chooser: FirstChooser.new)

    result = suggester.suggest("Cotton t-shirt, blue, size M")

    assert result.is_a?(Hash)
    %i[commodity_code confidence reasoning category validated official_description duty_rate].each do |key|
      assert result.key?(key), "expected result to carry #{key}"
    end
    assert_equal "6109100010", result[:commodity_code]
    assert_match(/\A\d{10}\z/, result[:commodity_code])
    assert_equal true, result[:validated]
    assert result[:official_description].present?
  end

  test "marks the suggestion unvalidated when the walked code is not in the tariff" do
    stub_full_tariff(validated: false)
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(ANALYSIS.dup), chooser: FirstChooser.new)

    result = suggester.suggest("Cotton t-shirt")

    assert_equal "6109100010", result[:commodity_code]
    assert_equal false, result[:validated]
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------

  test "returns nil when the analyzer fails" do
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(nil), chooser: FirstChooser.new)

    assert_nil suggester.suggest("Some product")
  end

  test "returns nil when the chooser cannot decide" do
    stub_full_tariff(validated: true)
    null_chooser = Class.new(Classification::Chooser) { def choose(**) = nil }.new
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(ANALYSIS.dup), chooser: null_chooser)

    assert_nil suggester.suggest("Cotton t-shirt")
  end

  test "never raises when the tariff API errors mid-walk" do
    stub_request(:get, /trade-tariff\.service\.gov\.uk/).to_raise(Faraday::ConnectionFailed.new("refused"))
    suggester = LlmCommoditySuggester.new(analyzer: FakeAnalyzer.new(ANALYSIS.dup), chooser: FirstChooser.new)

    assert_nothing_raised { suggester.suggest("Cotton t-shirt") }
  end

  # ---------------------------------------------------------------------------
  # Legacy delegation
  # ---------------------------------------------------------------------------

  test "delegates to LegacyCommoditySuggester when TARIFFIK_PIPELINE=legacy" do
    with_env("TARIFFIK_PIPELINE", "legacy") do
      stub_request(:get, /trade-tariff\.service\.gov\.uk\/api\/v2\/search/)
        .to_return(status: 200, headers: json_headers, body: empty_search.to_json)
      stub_commodity_suggestion(code: "6109100010", confidence: 0.8, reasoning: "Legacy single-shot")
      stub_commodity("6109100010", validated: true)

      result = LlmCommoditySuggester.new.suggest("Cotton t-shirt")

      assert_equal "6109100010", result[:commodity_code]
      assert_equal true, result[:validated]
    end
  end

  private

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end

  def json_headers = { "Content-Type" => "application/json" }

  # Stubs every tariff endpoint the pipeline touches for a cotton t-shirt that
  # walks 6109 -> Of cotton -> T-shirts -> 6109100010.
  def stub_full_tariff(validated:)
    stub_request(:get, /#{Regexp.escape(API)}\/search/)
      .to_return(status: 200, headers: json_headers, body: search_hit("6109100010", "T-shirts, cotton", 90).to_json)

    stub_request(:get, "#{API}/chapters")
      .to_return(status: 200, headers: json_headers, body: {
        data: [ { type: "chapter", attributes: { goods_nomenclature_item_id: "6100000000", formatted_description: "Articles of apparel, knitted" } } ]
      }.to_json)

    stub_request(:get, "#{API}/chapters/61")
      .to_return(status: 200, headers: json_headers, body: {
        data: { type: "chapter", attributes: { goods_nomenclature_item_id: "6100000000", formatted_description: "Apparel", chapter_note: "1. Chapter 61 note." } },
        included: [ { type: "heading", attributes: { goods_nomenclature_item_id: "6109000000", formatted_description: "T-shirts, singlets and other vests, knitted" } } ]
      }.to_json)

    stub_request(:get, "#{API}/headings/6109")
      .to_return(status: 200, headers: json_headers, body: {
        data: { type: "heading", attributes: { goods_nomenclature_item_id: "6109000000", formatted_description: "T-shirts", declarable: false } },
        included: [
          commodity_row("6109100000", "80", 1, false, "Of cotton"),
          commodity_row("6109100010", "80", 2, true, "T-shirts"),
          commodity_row("6109100090", "80", 2, true, "Other")
        ]
      }.to_json)

    stub_commodity("6109100010", validated: validated)
  end

  def commodity_row(item_id, suffix, indents, declarable, description)
    { type: "commodity", attributes: { goods_nomenclature_item_id: item_id, producline_suffix: suffix, number_indents: indents, declarable: declarable, formatted_description: description } }
  end

  def search_hit(code, description, score)
    {
      data: {
        attributes: {
          type: "fuzzy_match",
          goods_nomenclature_match: {
            commodities: [ { "_source" => { "goods_nomenclature_item_id" => code, "description" => description }, "_score" => score } ],
            headings: []
          }
        }
      }
    }
  end

  def empty_search
    { data: { attributes: { type: "fuzzy_match", goods_nomenclature_match: { commodities: [], headings: [] } } } }
  end

  def stub_commodity(code, validated:)
    if validated
      stub_request(:get, "#{API}/commodities/#{code}")
        .to_return(status: 200, headers: json_headers, body: {
          data: { attributes: { goods_nomenclature_item_id: code, formatted_description: "T-shirts, of cotton, knitted" } },
          included: [ { type: "measure", attributes: { duty_expression: { formatted_base: "12.0%" } } } ]
        }.to_json)
    else
      stub_request(:get, "#{API}/commodities/#{code}").to_return(status: 404, body: { error: "Not found" }.to_json)
    end
  end
end
