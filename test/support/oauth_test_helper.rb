# frozen_string_literal: true

# Helpers for the OAuth 2.1 authorization server and the MCP resource server.
module OauthTestHelper
  MCP_RESOURCE = "http://www.example.com/mcp"

  # A dynamically registered public client, as an MCP client would create.
  def create_oauth_application(name: "Test MCP client", redirect_uri: "http://localhost:9999/callback", confidential: false)
    application = Doorkeeper::Application.new(
      name: name,
      redirect_uri: redirect_uri,
      scopes: "mcp",
      confidential: confidential
    )
    application.secret = nil unless confidential
    application.save!
    application
  end

  # An access token as the authorization server would issue it, audience-bound
  # to the MCP endpoint unless told otherwise.
  def create_access_token(user:, application: nil, resource: MCP_RESOURCE, scopes: "mcp", expires_in: 3600)
    Doorkeeper::AccessToken.create!(
      application: application || create_oauth_application,
      resource_owner_id: user.id,
      scopes: scopes,
      expires_in: expires_in,
      resource: resource
    )
  end

  def oauth_headers(token)
    raw = token.is_a?(String) ? token : token.token
    {
      "Authorization" => "Bearer #{raw}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  def mcp_post(message, token:)
    post "/mcp", params: message.to_json, headers: oauth_headers(token)
  end

  def rpc(method, params = nil, id: 1)
    { "jsonrpc" => "2.0", "id" => id, "method" => method }.tap do |message|
      message["params"] = params if params
    end
  end

  def tool_call(name, arguments, id: 1)
    rpc("tools/call", { "name" => name, "arguments" => arguments }, id: id)
  end

  # tools/call results carry their payload as JSON inside a text content block.
  def tool_payload(result)
    JSON.parse(result[:content].first[:text], symbolize_names: true)
  end

  # PKCE pair for an authorization code flow.
  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [ verifier, challenge ]
  end
end
