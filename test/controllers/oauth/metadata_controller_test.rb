require "test_helper"

class Oauth::MetadataControllerTest < ActionDispatch::IntegrationTest
  # Discovery has to work before the client has any credentials, so none of
  # these may require authentication.

  test "protected resource metadata is public and names the authorization server" do
    get "/.well-known/oauth-protected-resource"

    assert_response :success
    body = json_response
    assert_equal "http://www.example.com/mcp", body[:resource]
    assert_equal [ "http://www.example.com" ], body[:authorization_servers]
    assert_includes body[:scopes_supported], "mcp"
    assert_equal [ "header" ], body[:bearer_methods_supported]
  end

  test "protected resource metadata is also served with the resource path appended" do
    # Clients probe /.well-known/oauth-protected-resource/mcp for a resource
    # that lives under a path.
    get "/.well-known/oauth-protected-resource/mcp"

    assert_response :success
    assert_equal "http://www.example.com/mcp", json_response[:resource]
  end

  test "authorization server metadata advertises the endpoints a client needs" do
    get "/.well-known/oauth-authorization-server"

    assert_response :success
    body = json_response
    assert_equal "http://www.example.com", body[:issuer]
    assert_equal "http://www.example.com/oauth/authorize", body[:authorization_endpoint]
    assert_equal "http://www.example.com/oauth/token", body[:token_endpoint]
    assert_equal "http://www.example.com/oauth/register", body[:registration_endpoint]
    assert_equal [ "code" ], body[:response_types_supported]
    assert_includes body[:grant_types_supported], "authorization_code"
    assert_includes body[:grant_types_supported], "refresh_token"
  end

  test "exactly one scope is advertised" do
    # A stray entry here becomes a scope clients try to request, so it is worth
    # pinning: `optional_scopes []` once registered a scope literally named "[]".
    get "/.well-known/oauth-protected-resource"
    assert_equal [ "mcp" ], json_response[:scopes_supported]

    get "/.well-known/oauth-authorization-server"
    assert_equal [ "mcp" ], json_response[:scopes_supported]
  end

  test "only S256 is advertised for PKCE" do
    # `plain` gives none of PKCE's protection and OAuth 2.1 forbids relying on it.
    get "/.well-known/oauth-authorization-server"

    assert_equal [ "S256" ], json_response[:code_challenge_methods_supported]
  end

  test "authorization server metadata is served with a path appended too" do
    get "/.well-known/oauth-authorization-server/mcp"

    assert_response :success
    assert_equal "http://www.example.com", json_response[:issuer]
  end

  private

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end
