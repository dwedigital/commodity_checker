require "test_helper"

class Api::V1::ExtensionControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @extension_id = "ext_#{SecureRandom.uuid}"
  end

  # === Usage Endpoint ===

  test "usage returns stats for anonymous extension" do
    # Create some lookups
    2.times do |i|
      ExtensionLookup.create!(
        extension_id: @extension_id,
        url: "https://example.com/#{i}",
        commodity_code: "6109100010"
      )
    end

    get api_v1_extension_usage_url(extension_id: @extension_id),
        headers: { "Accept" => "application/json" }

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 2, json["lookups_used"]
    assert_equal ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT - 2, json["lookups_remaining"]
    assert_equal ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT, json["limit"]
    assert_equal "anonymous", json["type"]
  end

  test "usage requires extension_id" do
    get api_v1_extension_usage_url,
        headers: { "Accept" => "application/json" }

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "extension_id is required", json["error"]
  end

  # === Token Exchange Endpoint ===

  test "exchange_token returns token for valid auth code" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    post api_v1_extension_token_url,
         params: { code: raw_code, extension_id: @extension_id },
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :success
    json = JSON.parse(response.body)

    assert json["token"].present?
    assert json["token"].start_with?("ext_tk_test_")  # test environment prefix
    assert_equal @user.email, json["user"]["email"]
    assert json["user"]["subscription_tier"].present?
  end

  test "exchange_token fails for invalid code" do
    post api_v1_extension_token_url,
         params: { code: "invalid_code", extension_id: @extension_id },
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "invalid_code", json["error"]
  end

  test "exchange_token requires code and extension_id" do
    post api_v1_extension_token_url,
         params: {},
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "code and extension_id are required", json["error"]
  end

  # === Revoke Token Endpoint ===

  test "revoke_token revokes authenticated token" do
    token = @user.extension_tokens.create!(name: "Test")
    raw_token = token.raw_token

    delete api_v1_extension_token_url,
           headers: {
             "Accept" => "application/json",
             "Authorization" => "Bearer #{raw_token}"
           }

    assert_response :success
    token.reload
    assert token.revoked?
  end

  test "revoke_token requires authentication" do
    delete api_v1_extension_token_url,
           headers: { "Accept" => "application/json" }

    assert_response :unauthorized
  end

  # === Lookup Endpoint (Anonymous) ===

  test "anonymous lookup succeeds with extension_id" do
    # Stub the Claude API response (used by LlmCommoditySuggester -> ApiCommodityService)
    stub_commodity_suggestion(
      code: "6109100010",
      confidence: 0.85,
      reasoning: "Cotton t-shirt"
    )

    # Stub the tariff API search and validation
    stub_request(:get, /trade-tariff.service.gov.uk.*search/)
      .to_return(status: 200, body: { type: "fuzzy_match", results: [] }.to_json)
    stub_request(:get, /trade-tariff.service.gov.uk.*commodities/)
      .to_return(status: 200, body: { data: { attributes: { description: "T-shirts" } } }.to_json)

    post api_v1_extension_lookup_url,
         params: { extension_id: @extension_id, description: "Cotton t-shirt" },
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "6109100010", json["commodity_code"]
    assert json["extension_usage"].present?
  end

  test "anonymous lookup requires extension_id" do
    post api_v1_extension_lookup_url,
         params: { description: "Cotton t-shirt" },
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "extension_id is required for anonymous lookups", json["error"]
  end

  test "anonymous lookup fails when limit exhausted" do
    # Use up all lookups
    ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT.times do |i|
      ExtensionLookup.create!(
        extension_id: @extension_id,
        url: "https://example.com/#{i}",
        commodity_code: "6109100010"
      )
    end

    post api_v1_extension_lookup_url,
         params: { extension_id: @extension_id, description: "Cotton t-shirt" },
         headers: { "Accept" => "application/json" },
         as: :json

    assert_response :payment_required
    json = JSON.parse(response.body)
    assert_equal "free_lookups_exhausted", json["error"]
  end

  # === Lookup Endpoint (Authenticated) ===

  test "authenticated lookup succeeds with valid token" do
    token = @user.extension_tokens.create!(name: "Test")
    raw_token = token.raw_token

    # Stub the Claude API response
    stub_commodity_suggestion(
      code: "6109100010",
      confidence: 0.85,
      reasoning: "Cotton t-shirt"
    )

    # Stub the tariff API
    stub_request(:get, /trade-tariff.service.gov.uk.*search/)
      .to_return(status: 200, body: { type: "fuzzy_match", results: [] }.to_json)
    stub_request(:get, /trade-tariff.service.gov.uk.*commodities/)
      .to_return(status: 200, body: { data: { attributes: { description: "T-shirts" } } }.to_json)

    post api_v1_extension_lookup_url,
         params: { description: "Cotton t-shirt" },
         headers: {
           "Accept" => "application/json",
           "Authorization" => "Bearer #{raw_token}"
         },
         as: :json

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "6109100010", json["commodity_code"]
    assert json["user_usage"].present?
  end

  test "authenticated lookup fails with revoked token" do
    token = @user.extension_tokens.create!(name: "Test")
    raw_token = token.raw_token
    token.revoke!

    post api_v1_extension_lookup_url,
         params: { description: "Cotton t-shirt" },
         headers: {
           "Accept" => "application/json",
           "Authorization" => "Bearer #{raw_token}"
         },
         as: :json

    assert_response :unauthorized
  end
end
