# frozen_string_literal: true

# OAuth 2.1 authorization server for the MCP endpoint.
#
# The MCP authorization spec (2025-06-18) makes Tariffik both the resource
# server (/mcp) and its own authorization server. Doorkeeper issues and
# validates tokens; RFC 7591 registration, RFC 8414/9728 metadata and RFC 8707
# audience binding live in app/controllers/oauth.
Doorkeeper.configure do
  orm :active_record

  # Our own layout, flash and Devise helpers on the consent screen.
  base_controller "ApplicationController"

  # Who is granting access. Google sign-in is the only way to become one.
  resource_owner_authenticator do
    current_user || begin
      session[:user_return_to] = request.fullpath
      redirect_to new_user_session_path, alert: "Sign in to connect an application to Tariffik."
    end
  end

  admin_authenticator do
    current_user&.admin? || redirect_to(new_user_session_path)
  end

  # Only the authorization code flow. No implicit (removed in OAuth 2.1), no
  # password grant, and no client credentials: every token must belong to a
  # person, because MCP tools act on that person's account.
  grant_flows %w[authorization_code]

  # PKCE is mandatory in the MCP spec, and `plain` is not good enough.
  force_pkce
  pkce_code_challenge_methods %w[S256]

  # Short-lived access tokens, per the spec's guidance. Refresh tokens rotate:
  # the `previous_refresh_token` column makes Doorkeeper revoke the old one once
  # the new access token is used, which OAuth 2.1 requires for public clients.
  access_token_expires_in 1.hour
  authorization_code_expires_in 10.minutes
  use_refresh_token

  # If an authorization code is replayed, revoke the tokens it already produced.
  revoke_previous_authorization_code_token

  default_scopes :mcp

  # RFC 8707. `resource` is captured on the authorize request and carried onto
  # the grant, the access token, and any refreshed token, so the MCP endpoint
  # can check the token was issued for it. The column exists on both tables.
  custom_access_token_attributes [ :resource ]

  # MCP clients are public: they register dynamically and hold no secret.
  allow_blank_redirect_uri false

  # The spec allows loopback redirect URIs, which is how a local MCP client
  # (Claude Code, Cursor) receives its callback. Everything else must be HTTPS.
  force_ssl_in_redirect_uri do |uri|
    !%w[localhost 127.0.0.1 ::1].include?(uri.host)
  end

  # Consent is always shown. Skipping it is what enables the confused-deputy
  # attack the MCP security guidance calls out, since clients register
  # dynamically and are not vetted.
  skip_authorization { false }

  # A client that registered without a secret is public and authenticates with
  # PKCE alone; one that has a secret must present it.
  enforce_configured_scopes
end
