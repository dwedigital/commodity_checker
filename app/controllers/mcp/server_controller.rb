# frozen_string_literal: true

# Model Context Protocol endpoint (Streamable HTTP transport, stateless).
#
# POST /mcp speaks JSON-RPC 2.0 and is an OAuth 2.1 resource server: the only
# way in is an access token issued by Tariffik's own authorization server, which
# in turn only issues tokens to someone who has signed in with Google and
# approved the client. API keys are not accepted here; they remain the
# credential for the REST API at /api/v1.
#
#   claude mcp add --transport http tariffik https://tariffik.com/mcp
#
# The client discovers everything it needs from the 401 this returns: the
# WWW-Authenticate header names the protected resource metadata, which names the
# authorization server, which advertises the authorize, token and registration
# endpoints.
module Mcp
  class ServerController < ActionController::API
    JSONRPC_VERSION = "2.0"

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    before_action :authenticate_access_token!

    rescue_from StandardError, with: :jsonrpc_internal_error

    # POST /mcp
    def handle
      message = parse_body
      return render_jsonrpc_error(nil, PARSE_ERROR, "Parse error") if message == :parse_error

      response.headers["MCP-Protocol-Version"] = negotiated_protocol_version

      if message.is_a?(Array)
        handle_batch(message)
      else
        handle_single(message)
      end
    end

    # GET/DELETE /mcp — no server-initiated stream and no session to end.
    def unsupported
      render json: error_body(nil, METHOD_NOT_FOUND, "This MCP server only supports POST"),
             status: :method_not_allowed
    end

    private

    attr_reader :access_token

    # OAuth 2.1 Section 5.2 token validation, plus the audience check the MCP
    # spec requires so a token minted for some other resource cannot be replayed
    # here.
    def authenticate_access_token!
      raw = bearer_token
      return unauthorized!("invalid_request", "An OAuth access token is required") if raw.blank?

      token = Doorkeeper::AccessToken.by_token(raw)
      return unauthorized!("invalid_token", "The access token is invalid, expired, or revoked") unless token&.accessible?
      return forbidden!("insufficient_scope", "The access token is missing the mcp scope") unless token.scopes.include?("mcp")
      return unauthorized!("invalid_token", "The access token was not issued for this MCP server") unless audience_matches?(token)
      return unauthorized!("invalid_token", "The access token has no user attached") unless resource_owner(token)

      # MCP used to require an API key, which requires a Starter subscription.
      # OAuth would otherwise hand the same tools to every free account, so the
      # entitlement is enforced here instead of by the credential.
      unless resource_owner(token).has_api_access?
        return forbidden!("insufficient_scope",
                          "MCP access requires a Starter subscription or higher")
      end

      @access_token = token
    end

    # RFC 8707. A token carries the `resource` its client asked for. When it is
    # present it has to name this endpoint. When it is absent the token is still
    # ours to trust, because this authorization server protects exactly one
    # resource and therefore cannot have issued it for anything else — but if a
    # second protected resource is ever added, this has to become strict.
    def audience_matches?(token)
      requested = token.try(:resource)
      return true if requested.blank?

      canonical(requested) == canonical(resource_identifier)
    end

    def canonical(uri)
      uri.to_s.strip.downcase.sub(%r{/\z}, "")
    end

    def resource_identifier
      "#{request.base_url}/mcp"
    end

    def resource_metadata_url
      "#{request.base_url}/.well-known/oauth-protected-resource/mcp"
    end

    def bearer_token
      header = request.authorization.to_s
      return nil unless header.match?(/\ABearer\s+/i)

      header.split(" ", 2).last.presence
    end

    def resource_owner(token = access_token)
      @resource_owner ||= User.find_by(id: token.resource_owner_id)
    end

    # RFC 9728 Section 5.1: the 401 tells the client where to find the metadata
    # that starts the OAuth flow.
    def unauthorized!(error, description)
      response.headers["WWW-Authenticate"] = www_authenticate(error, description)
      render json: { error: error, error_description: description }, status: :unauthorized
    end

    def forbidden!(error, description)
      response.headers["WWW-Authenticate"] = www_authenticate(error, description)
      render json: { error: error, error_description: description }, status: :forbidden
    end

    def www_authenticate(error, description)
      %(Bearer error="#{error}", error_description="#{description}", ) +
        %(resource_metadata="#{resource_metadata_url}")
    end

    def handle_single(message)
      return render_jsonrpc_error(nil, INVALID_REQUEST, "Invalid Request") unless message.is_a?(Hash)

      result = dispatch_message(message)

      # A JSON-RPC notification carries no id and gets no response body.
      return head(:accepted) if result == :no_response

      render json: result, status: :ok
    end

    def handle_batch(messages)
      return render_jsonrpc_error(nil, INVALID_REQUEST, "Invalid Request") if messages.empty?

      responses = messages.map { |message| message.is_a?(Hash) ? dispatch_message(message) : invalid_request_body }
                          .reject { |result| result == :no_response }

      return head(:accepted) if responses.empty?

      render json: responses, status: :ok
    end

    def dispatch_message(message)
      id = message["id"]
      method = message["method"]
      params = message["params"] || {}

      case method
      when "initialize"         then success(id, initialize_result(params))
      when "ping"               then success(id, {})
      when "tools/list"         then success(id, { tools: ToolCatalog.tools })
      when "tools/call"         then tools_call(id, params)
      when %r{\Anotifications/} then :no_response
      when nil                  then notification?(message) ? :no_response : invalid_request_body(id)
      else
        notification?(message) ? :no_response : error_body(id, METHOD_NOT_FOUND, "Method not found: #{method}")
      end
    end

    def initialize_result(params)
      {
        protocolVersion: ToolCatalog.negotiate_protocol_version(params["protocolVersion"]),
        capabilities: { tools: { listChanged: false } },
        serverInfo: ToolCatalog.server_info,
        instructions: ToolCatalog::INSTRUCTIONS
      }
    end

    def tools_call(id, params)
      name = params["name"]
      return error_body(id, INVALID_PARAMS, "Missing tool name") if name.blank?
      return error_body(id, INVALID_PARAMS, "Unknown tool: #{name}") unless ToolCatalog.tool?(name)

      payload = ToolRunner.new(user: resource_owner).call(name, params["arguments"])

      success(id, {
        content: [ { type: "text", text: JSON.pretty_generate(payload) } ],
        isError: payload.key?(:error)
      })
    end

    def parse_body
      raw = request.raw_post
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      :parse_error
    end

    def notification?(message)
      !message.key?("id")
    end

    def negotiated_protocol_version
      ToolCatalog.negotiate_protocol_version(request.headers["MCP-Protocol-Version"])
    end

    def success(id, result)
      { jsonrpc: JSONRPC_VERSION, id: id, result: result }
    end

    def error_body(id, code, message)
      { jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message } }
    end

    def invalid_request_body(id = nil)
      error_body(id, INVALID_REQUEST, "Invalid Request")
    end

    def render_jsonrpc_error(id, code, message)
      render json: error_body(id, code, message), status: :ok
    end

    def jsonrpc_internal_error(exception)
      Rails.logger.error("MCP error: #{exception.class} - #{exception.message}")
      Rails.logger.error(exception.backtrace.first(10).join("\n"))

      render json: error_body(nil, INTERNAL_ERROR, "Internal error"), status: :internal_server_error
    end
  end
end
