require "test_helper"

# The whole journey an MCP client makes: discover, register, get consent,
# exchange a code for a token, and call the MCP endpoint with it.
class McpOauthFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  REDIRECT_URI = "http://localhost:8765/callback"

  def setup
    @user = users(:one) # starter tier
  end

  test "a client discovers, registers, is authorized, and calls MCP" do
    # 1. An unauthenticated MCP call tells the client where to start.
    post "/mcp", params: rpc("tools/list").to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    metadata_url = response.headers["WWW-Authenticate"][/resource_metadata="([^"]+)"/, 1]
    assert metadata_url.present?

    # 2. Protected resource metadata names the authorization server.
    get URI.parse(metadata_url).path
    assert_response :success
    authorization_server = JSON.parse(response.body)["authorization_servers"].first

    # 3. Authorization server metadata names the endpoints.
    get "#{URI.parse(authorization_server).path}/.well-known/oauth-authorization-server".squeeze("/")
    assert_response :success
    as = JSON.parse(response.body)

    # 4. The client registers itself.
    post URI.parse(as["registration_endpoint"]).path,
         params: { client_name: "Claude Code", redirect_uris: [ REDIRECT_URI ] }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :created
    client_id = JSON.parse(response.body)["client_id"]

    # 5. The person signs in and approves it.
    sign_in @user
    verifier, challenge = pkce_pair

    get URI.parse(as["authorization_endpoint"]).path, params: authorize_params(client_id, challenge)
    assert_response :success
    assert_match "Claude Code", response.body

    post "/oauth/authorize", params: authorize_params(client_id, challenge)
    assert_response :redirect
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    assert code.present?, "expected an authorization code in the redirect"

    # 6. The client exchanges the code, proving it with the PKCE verifier.
    post URI.parse(as["token_endpoint"]).path, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: REDIRECT_URI,
      client_id: client_id,
      code_verifier: verifier,
      resource: OauthTestHelper::MCP_RESOURCE
    }
    assert_response :success
    tokens = JSON.parse(response.body)
    assert tokens["access_token"].present?
    assert tokens["refresh_token"].present?
    assert_equal "mcp", tokens["scope"]

    # The token is bound to the MCP endpoint it was requested for.
    issued = Doorkeeper::AccessToken.by_token(tokens["access_token"])
    assert_equal OauthTestHelper::MCP_RESOURCE, issued.resource

    # 7. And it works on the MCP endpoint.
    mcp_post rpc("tools/list"), token: tokens["access_token"]
    assert_response :success
    assert_equal 5, JSON.parse(response.body, symbolize_names: true)[:result][:tools].size
  end

  test "the consent forms opt out of Turbo" do
    # Turbo cannot follow the cross-origin redirect back to the client's
    # callback, so with Turbo handling the submit the browser never leaves the
    # consent page. Integration tests do not run Turbo, so this is asserted on
    # the markup instead.
    application = create_oauth_application(redirect_uri: REDIRECT_URI)
    sign_in @user
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params(application.uid, challenge)

    assert_response :success
    forms = response.body.scan(/<form[^>]*action="[^"]*oauth\/authorize[^"]*"[^>]*>/)
    assert_equal 2, forms.size, "expected the connect and cancel forms"
    forms.each do |form|
      assert_match(/data-turbo="false"/, form)
    end
  end

  test "the authorization code cannot be exchanged without the PKCE verifier" do
    code = authorization_code_for(pkce_pair.last)

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: REDIRECT_URI, client_id: @client_id
    }

    assert_response :bad_request
  end

  test "the authorization code cannot be exchanged with the wrong verifier" do
    code = authorization_code_for(pkce_pair.last)

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: REDIRECT_URI, client_id: @client_id,
      code_verifier: pkce_pair.first
    }

    assert_response :bad_request
  end

  test "an authorization request without PKCE is refused" do
    application = create_oauth_application(redirect_uri: REDIRECT_URI)
    sign_in @user

    get "/oauth/authorize", params: {
      client_id: application.uid, redirect_uri: REDIRECT_URI,
      response_type: "code", scope: "mcp"
    }

    # force_pkce means no challenge, no authorization.
    assert_response :bad_request
    assert_no_match(/Connect #{application.name}/, response.body)
  end

  test "authorizing requires signing in first" do
    application = create_oauth_application(redirect_uri: REDIRECT_URI)
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params(application.uid, challenge)

    assert_redirected_to new_user_session_path
  end

  test "a refreshed token keeps its audience binding" do
    code = authorization_code_for(pkce_pair_stored.last)
    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
      client_id: @client_id, code_verifier: pkce_pair_stored.first,
      resource: OauthTestHelper::MCP_RESOURCE
    }
    assert_response :success
    refresh_token = JSON.parse(response.body)["refresh_token"]

    post "/oauth/token", params: {
      grant_type: "refresh_token", refresh_token: refresh_token, client_id: @client_id
    }

    assert_response :success
    refreshed = Doorkeeper::AccessToken.by_token(JSON.parse(response.body)["access_token"])
    assert_equal OauthTestHelper::MCP_RESOURCE, refreshed.resource,
                 "a refreshed token must stay bound to the resource it was issued for"

    mcp_post rpc("ping"), token: refreshed.token
    assert_response :success
  end

  test "a redirect URI that was not registered is refused" do
    application = create_oauth_application(redirect_uri: REDIRECT_URI)
    sign_in @user
    _verifier, challenge = pkce_pair

    get "/oauth/authorize", params: authorize_params(application.uid, challenge)
                              .merge(redirect_uri: "http://localhost:8765/somewhere-else")

    # Exact matching against the registered URI, so an attacker cannot redirect
    # the authorization code somewhere of their choosing.
    assert_response :bad_request
    assert_no_match(/Connect #{application.name}/, response.body)
  end

  private

  def authorize_params(client_id, challenge)
    {
      client_id: client_id,
      redirect_uri: REDIRECT_URI,
      response_type: "code",
      scope: "mcp",
      state: "opaque-state",
      code_challenge: challenge,
      code_challenge_method: "S256",
      resource: OauthTestHelper::MCP_RESOURCE
    }
  end

  # Memoised so a test can reuse the same verifier/challenge pair.
  def pkce_pair_stored
    @pkce_pair_stored ||= pkce_pair
  end

  # Walks as far as a usable authorization code, for tests about the exchange.
  def authorization_code_for(challenge)
    application = create_oauth_application(redirect_uri: REDIRECT_URI)
    @client_id = application.uid
    sign_in @user

    post "/oauth/authorize", params: authorize_params(@client_id, challenge)
    assert_response :redirect
    Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
  end
end
