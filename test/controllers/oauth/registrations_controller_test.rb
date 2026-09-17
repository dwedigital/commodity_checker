require "test_helper"

class Oauth::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  # RFC 7591. Registration is deliberately unauthenticated: an MCP client has no
  # credentials yet, and registering grants nothing on its own.

  test "registers a public client and returns no secret" do
    assert_difference -> { Doorkeeper::Application.count }, 1 do
      register(client_name: "Claude Code", redirect_uris: [ "http://localhost:8765/callback" ])
    end

    assert_response :created
    body = json_response
    assert body[:client_id].present?
    assert_nil body[:client_secret], "a public client must not be given a secret"
    assert_equal "none", body[:token_endpoint_auth_method]
    assert_equal [ "http://localhost:8765/callback" ], body[:redirect_uris]
    assert_equal "mcp", body[:scope]
  end

  test "registers a confidential client with a secret when one is asked for" do
    register(client_name: "Server app",
             redirect_uris: [ "https://example.com/callback" ],
             token_endpoint_auth_method: "client_secret_basic")

    assert_response :created
    assert json_response[:client_secret].present?
    assert_equal 0, json_response[:client_secret_expires_at]
  end

  test "redirect_uris is required" do
    assert_no_difference -> { Doorkeeper::Application.count } do
      register(client_name: "No redirect")
    end

    assert_response :bad_request
    assert_equal "invalid_redirect_uri", json_response[:error]
  end

  test "plain http is refused unless it is loopback" do
    assert_no_difference -> { Doorkeeper::Application.count } do
      register(client_name: "Insecure", redirect_uris: [ "http://evil.example.com/callback" ])
    end

    assert_response :bad_request
    assert_equal "invalid_redirect_uri", json_response[:error]
  end

  test "loopback http is allowed so a local client can catch its callback" do
    [ "http://localhost:9999/cb", "http://127.0.0.1:9999/cb" ].each do |uri|
      register(client_name: "Local", redirect_uris: [ uri ])
      assert_response :created, "#{uri} should be allowed"
    end
  end

  test "a redirect URI with a fragment is refused" do
    register(client_name: "Fragment", redirect_uris: [ "https://example.com/cb#part" ])

    assert_response :bad_request
  end

  test "unsupported grant types are refused" do
    register(client_name: "Implicit",
             redirect_uris: [ "https://example.com/cb" ],
             grant_types: [ "implicit" ])

    assert_response :bad_request
    assert_equal "invalid_client_metadata", json_response[:error]
  end

  test "too many redirect URIs are refused" do
    register(client_name: "Greedy",
             redirect_uris: (1..11).map { |i| "https://example.com/cb#{i}" })

    assert_response :bad_request
  end

  private

  def register(**params)
    post "/oauth/register", params: params.to_json,
                            headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end
