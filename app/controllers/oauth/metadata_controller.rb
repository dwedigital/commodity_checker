# frozen_string_literal: true

# OAuth discovery documents.
#
# An MCP client finds its way in by reading these: it gets a 401 from /mcp with
# a WWW-Authenticate header naming the protected resource metadata, reads that
# to find the authorization server, then reads the authorization server metadata
# to find the authorize, token and registration endpoints.
#
# ActionController::API, not ApplicationController: these are fetched by MCP
# clients rather than browsers, and ApplicationController's `allow_browser`
# check has no business judging them.
module Oauth
  class MetadataController < ActionController::API
    # The MCP endpoint this server protects, as an RFC 8707 canonical URI:
    # absolute, no fragment, no trailing slash.
    MCP_PATH = "/mcp"

    # GET /.well-known/oauth-authorization-server
    # RFC 8414.
    def authorization_server
      render json: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        introspection_endpoint: "#{issuer}/oauth/introspect",
        scopes_supported: scopes_supported,
        response_types_supported: [ "code" ],
        response_modes_supported: [ "query" ],
        grant_types_supported: [ "authorization_code", "refresh_token" ],
        # S256 only. OAuth 2.1 and the MCP spec both require PKCE, and `plain`
        # gives none of its protection.
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: [ "none", "client_secret_basic", "client_secret_post" ]
      }
    end

    # GET /.well-known/oauth-protected-resource
    # RFC 9728. Clients also probe the path-suffixed form for a resource that
    # lives under a path, so /.well-known/oauth-protected-resource/mcp routes
    # here too.
    def protected_resource
      render json: {
        resource: resource_identifier,
        authorization_servers: [ issuer ],
        scopes_supported: scopes_supported,
        bearer_methods_supported: [ "header" ]
      }
    end

    private

    # Derived from the request rather than configured, so the same code serves
    # localhost in development and https://tariffik.com in production.
    def issuer
      request.base_url
    end

    def resource_identifier
      "#{issuer}#{MCP_PATH}"
    end

    def scopes_supported
      Doorkeeper.config.scopes.to_a.presence || [ "mcp" ]
    end
  end
end
