require "test_helper"

class Mcp::ServerControllerTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  def setup
    @user = users(:one)          # starter tier, so entitled to MCP
    @token = create_access_token(user: @user)
  end

  # Authentication

  test "returns 401 without a token" do
    post "/mcp", params: rpc("tools/list").to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "returns 401 with an unknown token" do
    mcp_post rpc("tools/list"), token: "not-a-real-token"

    assert_response :unauthorized
  end

  test "an API key is no longer accepted" do
    # MCP moved to OAuth; API keys remain the credential for /api/v1 only.
    _api_key, raw_key = create_api_key(user: @user)

    mcp_post rpc("tools/list"), token: raw_key

    assert_response :unauthorized
  end

  test "a revoked token is rejected" do
    @token.update!(revoked_at: 1.minute.ago)

    mcp_post rpc("tools/list"), token: @token

    assert_response :unauthorized
  end

  test "an expired token is rejected" do
    @token.update!(created_at: 3.hours.ago, expires_in: 60)

    mcp_post rpc("tools/list"), token: @token

    assert_response :unauthorized
  end

  # The 401 is how a client discovers the OAuth flow (RFC 9728 section 5.1)

  test "401 points at the protected resource metadata" do
    post "/mcp", params: rpc("tools/list").to_json, headers: { "Content-Type" => "application/json" }

    header = response.headers["WWW-Authenticate"]
    assert header.present?, "WWW-Authenticate is required for MCP client discovery"
    assert_match(/\ABearer /, header)
    assert_match %r{resource_metadata="http://www\.example\.com/\.well-known/oauth-protected-resource/mcp"}, header
  end

  # Audience binding (RFC 8707)

  test "a token issued for a different resource is rejected" do
    other = create_access_token(user: @user, resource: "https://someone-elses-server.example/mcp")

    mcp_post rpc("tools/list"), token: other

    assert_response :unauthorized
    assert_match(/not issued for this MCP server/i, json_response[:error_description])
  end

  test "a token with no resource is accepted because this server issues for one resource only" do
    unbound = create_access_token(user: @user, resource: nil)

    mcp_post rpc("tools/list"), token: unbound

    assert_response :success
  end

  test "audience comparison ignores a trailing slash and case" do
    token = create_access_token(user: @user, resource: "HTTP://WWW.EXAMPLE.COM/mcp/")

    mcp_post rpc("tools/list"), token: token

    assert_response :success
  end

  # Scope and entitlement

  test "a token without the mcp scope is forbidden" do
    token = create_access_token(user: @user, scopes: "")

    mcp_post rpc("tools/list"), token: token

    assert_response :forbidden
  end

  test "a free account can use MCP" do
    # MCP is part of the free account now; the paid tier is about volume and API
    # access, not about whether an agent can connect at all.
    token = create_access_token(user: users(:free_user))

    mcp_post rpc("tools/list"), token: token

    assert_response :success
    assert_equal 5, json_response[:result][:tools].size
  end

  test "a free account at its monthly cap is refused a lookup, with a reason" do
    # Without this, giving free accounts MCP would make the monthly allowance
    # meaningless: an agent could call lookup_from_url all day.
    free_user = users(:free_user)
    User::FREE_MONTHLY_LOOKUP_LIMIT.times do |i|
      free_user.product_lookups.create!(url: "https://example.com/#{i}", lookup_type: :url)
    end
    token = create_access_token(user: free_user)

    mcp_post tool_call("lookup_from_description", { "description" => "Cotton t-shirt" }), token: token

    assert_response :success
    assert_equal true, json_response[:result][:isError]
    payload = tool_payload(json_response[:result])
    assert_equal "monthly_limit_reached", payload[:error]
    assert_match(/website, the browser extension and MCP/i, payload[:message])
  end

  test "reading is still allowed at the monthly cap" do
    # Searching the tariff and reading saved lookups are not lookups.
    free_user = users(:free_user)
    User::FREE_MONTHLY_LOOKUP_LIMIT.times do |i|
      free_user.product_lookups.create!(url: "https://example.com/#{i}", lookup_type: :url)
    end
    token = create_access_token(user: free_user)
    stub_tariff_api_search([ { code: "6109100010", description: "T-shirts, cotton", score: 95 } ])

    mcp_post tool_call("search_codes", { "query" => "cotton" }), token: token

    assert_equal false, json_response[:result][:isError]
  end

  test "a paid account is not capped" do
    # users(:one) is starter, and can_perform_lookup? is unlimited above free.
    User::FREE_MONTHLY_LOOKUP_LIMIT.times do |i|
      @user.product_lookups.create!(url: "https://example.com/paid#{i}", lookup_type: :url)
    end
    stub_tariff_api_search([ { code: "6109100010", description: "T-shirts, cotton", score: 95 } ])
    stub_tariff_api_commodity("6109100010", { code: "6109100010", description: "T-shirts, of cotton", duty_rate: "12%", notes: nil })
    stub_commodity_suggestion(code: "6109100010", confidence: 0.9, reasoning: "Knitted cotton t-shirt")

    mcp_post tool_call("lookup_from_description", { "description" => "Cotton t-shirt" }), token: @token

    assert_equal false, json_response[:result][:isError]
  end

  # Protocol

  test "initialize returns server info and capabilities" do
    mcp_post rpc("initialize", { "protocolVersion" => "2025-06-18", "capabilities" => {} }), token: @token

    assert_response :success
    result = json_response[:result]
    assert_equal "2025-06-18", result[:protocolVersion]
    assert_equal "tariffik", result[:serverInfo][:name]
    assert result[:capabilities][:tools].present?
  end

  test "initialize falls back to the servers protocol version for an unknown one" do
    mcp_post rpc("initialize", { "protocolVersion" => "1999-01-01" }), token: @token

    assert_equal Mcp::ToolCatalog::PROTOCOL_VERSION, json_response[:result][:protocolVersion]
  end

  test "initialized notification gets no body" do
    mcp_post({ "jsonrpc" => "2.0", "method" => "notifications/initialized" }, token: @token)

    assert_response :accepted
    assert_empty response.body
  end

  test "ping returns an empty result" do
    mcp_post rpc("ping"), token: @token

    assert_equal({}, json_response[:result])
  end

  test "unknown method returns method not found" do
    mcp_post rpc("resources/list"), token: @token

    assert_equal(-32601, json_response[:error][:code])
  end

  test "malformed JSON returns a parse error" do
    post "/mcp", params: "{not json", headers: oauth_headers(@token)

    assert_equal(-32700, json_response[:error][:code])
  end

  test "GET is not allowed" do
    get "/mcp", headers: oauth_headers(@token)

    assert_response :method_not_allowed
  end

  # tools/list

  test "tools/list advertises the five tools with input schemas" do
    mcp_post rpc("tools/list"), token: @token

    tools = json_response[:result][:tools]
    assert_equal %w[lookup_from_url lookup_from_description search_codes get_code list_recent_lookups],
                 tools.map { |tool| tool[:name] }
    tools.each do |tool|
      assert tool[:description].present?, "#{tool[:name]} is missing a description"
      assert_equal "object", tool[:inputSchema][:type]
    end
  end

  # tools/call

  test "search_codes returns tariff results as JSON text content" do
    stub_tariff_api_search([ { code: "6109100010", description: "T-shirts, cotton", score: 95 } ])

    mcp_post tool_call("search_codes", { "query" => "cotton t-shirt" }), token: @token

    result = json_response[:result]
    assert_equal false, result[:isError]
    payload = tool_payload(result)
    assert_equal "6109100010", payload[:results].first[:code]
    assert_equal "6109 10 0010", payload[:results].first[:formatted_code]
  end

  test "search_codes honours the limit argument" do
    stub_tariff_api_search((1..5).map { |i| { code: "610910001#{i}", description: "Shirt #{i}", score: 90 } })

    mcp_post tool_call("search_codes", { "query" => "shirt", "limit" => 2 }), token: @token

    assert_equal 2, tool_payload(json_response[:result])[:count]
  end

  test "get_code returns commodity details and tolerates formatted codes" do
    stub_tariff_api_commodity("6109100010", {
      code: "6109100010", description: "T-shirts, of cotton", duty_rate: "12%", notes: nil
    })

    mcp_post tool_call("get_code", { "code" => "6109 10 0010" }), token: @token

    payload = tool_payload(json_response[:result])
    assert_equal "6109100010", payload[:code]
    assert_equal "12%", payload[:duty_rate]
  end

  test "a tool failure is reported as isError not as a protocol error" do
    mcp_post tool_call("get_code", { "code" => "123" }), token: @token

    assert_response :success
    assert_nil json_response[:error]
    assert_equal true, json_response[:result][:isError]
  end

  test "unknown tool name is an invalid params error" do
    mcp_post tool_call("delete_everything", {}), token: @token

    assert_equal(-32602, json_response[:error][:code])
  end

  # Tools act on the token's own user

  test "lookup_from_description saves to the token owners account" do
    stub_tariff_api_search([ { code: "6109100010", description: "T-shirts, cotton", score: 95 } ])
    stub_tariff_api_commodity("6109100010", {
      code: "6109100010", description: "T-shirts, of cotton", duty_rate: "12%", notes: nil
    })
    stub_commodity_suggestion(code: "6109100010", confidence: 0.9, reasoning: "Knitted cotton t-shirt")

    assert_difference -> { @user.product_lookups.count }, 1 do
      mcp_post tool_call("lookup_from_description", { "description" => "Cotton t-shirt" }), token: @token
    end
  end

  test "a lookup cannot opt out of being recorded" do
    # ProductLookup is what lookups_this_month counts, so a save opt-out would
    # be an allowance opt-out. The argument is gone, and a caller passing it
    # anyway is still recorded.
    stub_tariff_api_search([ { code: "6109100010", description: "T-shirts, cotton", score: 95 } ])
    stub_tariff_api_commodity("6109100010", {
      code: "6109100010", description: "T-shirts, of cotton", duty_rate: "12%", notes: nil
    })
    stub_commodity_suggestion(code: "6109100010", confidence: 0.9, reasoning: "Knitted cotton t-shirt")

    assert_difference -> { @user.product_lookups.count }, 1 do
      mcp_post tool_call("lookup_from_description", { "description" => "Cotton t-shirt", "save" => false }), token: @token
    end

    assert_equal true, tool_payload(json_response[:result])[:saved_to_account]
  end

  test "the lookup tools do not advertise a save argument" do
    mcp_post rpc("tools/list"), token: @token

    tools = json_response[:result][:tools].index_by { |t| t[:name] }
    %w[lookup_from_url lookup_from_description].each do |name|
      assert_not_includes tools[name][:inputSchema][:properties].keys, :save,
                          "#{name} must not offer a way around the allowance"
    end
  end

  test "a free account cannot get past its cap by asking not to save" do
    free_user = users(:free_user)
    User::FREE_MONTHLY_LOOKUP_LIMIT.times do |i|
      free_user.product_lookups.create!(url: "https://example.com/#{i}", lookup_type: :url)
    end
    token = create_access_token(user: free_user)

    mcp_post tool_call("lookup_from_description", { "description" => "Cotton t-shirt", "save" => false }), token: token

    assert_equal true, json_response[:result][:isError]
    assert_equal "monthly_limit_reached", tool_payload(json_response[:result])[:error]
  end

  test "list_recent_lookups does not leak another users lookups" do
    users(:two).product_lookups.create!(url: "https://example.com/secret", lookup_type: :url, title: "Not mine")

    mcp_post tool_call("list_recent_lookups", {}), token: @token

    titles = tool_payload(json_response[:result])[:lookups].map { |l| l[:title] }
    assert_not_includes titles, "Not mine"
  end
end
