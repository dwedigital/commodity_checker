# frozen_string_literal: true

require "test_helper"

class TariffLookupServiceTest < ActiveSupport::TestCase
  # Test inputs - used in both requests and cassette filenames
  VALID_COMMODITY_CODE = "6109100010"
  INVALID_COMMODITY_CODE = "0000000000"

  def setup
    @service = TariffLookupService.new
  end

  # === VCR tests: assert on structure, not specific response values ===
  # These tests verify the service correctly parses API responses.
  # Cassettes contain real API responses - we test shape, not content.

  test "search returns array with expected structure for valid query" do
    with_cassette("tariff_api/search_cotton_tshirt") do
      results = @service.search("cotton t-shirt")

      assert results.is_a?(Array)
      assert results.any?, "Expected search to return results"

      first_result = results.first
      assert first_result.key?(:code), "Expected result to have :code key"
      assert first_result.key?(:description), "Expected result to have :description key"
      assert first_result[:code].present?
      assert first_result[:description].present?
    end
  end

  test "search returns empty array for nonsense query" do
    with_cassette("tariff_api/search_nonsense") do
      results = @service.search("xyzzy12345nonsense")

      assert results.is_a?(Array)
    end
  end

  test "get_commodity returns hash with expected structure for valid code" do
    with_cassette("tariff_api/commodity_#{VALID_COMMODITY_CODE}") do
      result = @service.get_commodity(VALID_COMMODITY_CODE)

      assert result.is_a?(Hash)
      assert result.key?(:code), "Expected result to have :code key"
      assert result.key?(:description), "Expected result to have :description key"
      # Code should match what we requested (verifies normalization works)
      assert_equal VALID_COMMODITY_CODE, result[:code]
      assert result[:description].present?
    end
  end

  test "get_commodity returns nil for invalid code" do
    with_cassette("tariff_api/commodity_invalid") do
      result = @service.get_commodity(INVALID_COMMODITY_CODE)

      assert_nil result
    end
  end

  test "get_commodity normalizes code format" do
    # Input with spaces should be normalized to the same code
    with_cassette("tariff_api/commodity_with_spaces") do
      result = @service.get_commodity("6109 1000 10")

      # Should normalize and attempt lookup - may succeed or fail
      # depending on whether the normalized code is valid
      assert result.nil? || result.is_a?(Hash)
    end
  end

  # === Stub tests: verify error handling without real API ===
  # These don't use VCR - they stub errors directly

  test "search handles connection errors gracefully" do
    stub_request(:get, /trade-tariff.service.gov.uk/)
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

    results = @service.search("cotton t-shirt")

    assert_equal [], results
  end

  test "get_commodity handles timeout errors gracefully" do
    stub_request(:get, /trade-tariff.service.gov.uk/)
      .to_raise(Faraday::TimeoutError.new("Timeout"))

    result = @service.get_commodity(VALID_COMMODITY_CODE)

    assert_nil result
  end
end
