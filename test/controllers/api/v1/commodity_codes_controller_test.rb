require "test_helper"

class Api::V1::CommodityCodesControllerTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  def setup
    @user = users(:one)
    @api_key, @raw_key = create_api_key(user: @user)
  end

  # Authentication Tests

  test "returns 401 without authorization header" do
    get api_v1_commodity_codes_search_path, params: { q: "cotton" }

    assert_response :unauthorized
    assert_equal "Invalid or missing API key", json_response[:message]
  end

  test "returns 401 with invalid API key" do
    get api_v1_commodity_codes_search_path,
        params: { q: "cotton" },
        headers: { "Authorization" => "Bearer tk_test_invalid123456" }

    assert_response :unauthorized
  end

  # Search Endpoint Tests

  test "search returns results for valid query" do
    stub_tariff_api_search([
      { code: "6109100010", description: "T-shirts, cotton", score: 95 }
    ])

    api_get api_v1_commodity_codes_search_path, raw_key: @raw_key, params: { q: "cotton t-shirt" }

    assert_response :success
    assert json_response[:results].is_a?(Array)
    assert_equal "6109100010", json_response[:results].first[:code]
  end

  test "search returns error for missing query" do
    api_get api_v1_commodity_codes_search_path, raw_key: @raw_key

    assert_response :bad_request
    assert_match(/Query parameter/, json_response[:message])
  end

  test "search includes usage stats in response" do
    stub_tariff_api_search([])

    api_get api_v1_commodity_codes_search_path, raw_key: @raw_key, params: { q: "test" }

    assert_response :success
    assert json_response[:usage].present?
    assert json_response[:usage][:requests_today].is_a?(Integer)
  end

  # Show Endpoint Tests

  test "show returns commodity details for valid code" do
    stub_tariff_api_commodity("6109100010", {
      code: "6109100010",
      description: "T-shirts, of cotton",
      duty_rate: "12%",
      notes: nil
    })

    api_get api_v1_path(id: "6109100010"), raw_key: @raw_key

    assert_response :success
    assert_equal "6109100010", json_response[:code]
    assert_equal "12%", json_response[:duty_rate]
  end

  test "show returns 404 for non-existent code" do
    stub_tariff_api_commodity("9999999999", nil)

    api_get api_v1_path(id: "9999999999"), raw_key: @raw_key

    assert_response :not_found
  end

  test "show returns error for invalid code format" do
    api_get api_v1_path(id: "123"), raw_key: @raw_key

    assert_response :bad_request
    assert_match(/minimum 6 digits/, json_response[:message])
  end

  # Suggest Endpoint Tests

  test "suggest returns commodity suggestion for description" do
    stub_tariff_api_search([
      { code: "6109100010", description: "T-shirts, cotton", score: 95 }
    ])
    stub_commodity_suggestion(
      code: "6109100010",
      confidence: 0.85,
      reasoning: "Cotton t-shirt"
    )
    stub_tariff_api_commodity("6109100010", {
      code: "6109100010",
      description: "T-shirts, of cotton",
      duty_rate: "12%"
    })

    api_post api_v1_commodity_codes_suggest_path,
             raw_key: @raw_key,
             params: { description: "Cotton t-shirt, blue, size M" }

    assert_response :success
    assert_equal "6109100010", json_response[:commodity_code]
    assert json_response[:confidence].present?
  end

  test "suggest returns error for missing description" do
    api_post api_v1_commodity_codes_suggest_path,
             raw_key: @raw_key,
             params: {}

    assert_response :bad_request
    assert_match(/description.*required/i, json_response[:message])
  end

  # Batch Endpoint Tests

  test "batch creates batch job for valid items" do
    api_post api_v1_commodity_codes_batch_path,
             raw_key: @raw_key,
             params: {
               items: [
                 { id: "sku-001", description: "Cotton shirt" },
                 { id: "sku-002", description: "Leather wallet" }
               ]
             }

    assert_response :accepted
    assert json_response[:batch_id].present?
    assert_equal "processing", json_response[:status]
    assert_equal 2, json_response[:total_items]
  end

  test "batch returns error for empty items" do
    api_post api_v1_commodity_codes_batch_path,
             raw_key: @raw_key,
             params: { items: [] }

    assert_response :bad_request
  end

  test "batch returns error for items exceeding batch size limit" do
    # Create too many items for trial tier
    trial_key, trial_raw = create_api_key(user: @user, tier: :trial, name: "Trial Key")
    items = (1..10).map { |i| { id: "sku-#{i}", description: "Product #{i}" } }

    api_post api_v1_commodity_codes_batch_path,
             raw_key: trial_raw,
             params: { items: items }

    assert_response :bad_request
    assert_match(/exceeds limit/i, json_response[:message])
  end

  test "batch validates item format" do
    api_post api_v1_commodity_codes_batch_path,
             raw_key: @raw_key,
             params: {
               items: [
                 { id: "sku-001" }  # Missing both description and url
               ]
             }

    assert_response :bad_request
    assert json_response[:errors].present?
  end

  # URL Suggestion Endpoint Tests

  test "suggest_from_url creates batch job for valid URL" do
    api_post api_v1_commodity_codes_suggest_from_url_path,
             raw_key: @raw_key,
             params: { url: "https://example.com/product/123" }

    assert_response :accepted
    assert json_response[:job_id].present?
    assert_equal "processing", json_response[:status]
  end

  test "suggest_from_url returns error for invalid URL" do
    api_post api_v1_commodity_codes_suggest_from_url_path,
             raw_key: @raw_key,
             params: { url: "not-a-valid-url" }

    assert_response :bad_request
    assert_match(/Invalid URL/i, json_response[:message])
  end

  # Rate Limiting Tests

  test "increments usage counter on successful request" do
    stub_tariff_api_search([])
    initial_count = @api_key.requests_today

    api_get api_v1_commodity_codes_search_path, raw_key: @raw_key, params: { q: "test" }

    @api_key.reload
    assert_equal initial_count + 1, @api_key.requests_today
  end
end
