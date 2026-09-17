# frozen_string_literal: true

# RFC 7591 Dynamic Client Registration.
#
# MCP clients are not known in advance and there is no sensible way to make a
# person register one by hand before connecting, so an unauthenticated client
# may register itself here and receive a client_id. That is what the RFC
# intends, and what Claude Code and claude.ai both expect.
#
# Registration on its own grants nothing: a registered client still has to send
# a person through the consent screen, and that person still has to sign in with
# Google and approve it. Rack::Attack throttles this endpoint so the open
# registration cannot be used to fill the table.
module Oauth
  class RegistrationsController < ActionController::API
    MAX_REDIRECT_URIS = 10
    SUPPORTED_GRANT_TYPES = %w[authorization_code refresh_token].freeze
    SUPPORTED_RESPONSE_TYPES = %w[code].freeze

    # POST /oauth/register
    def create
      redirect_uris = Array(params[:redirect_uris]).map(&:to_s).reject(&:blank?)

      error = validate(redirect_uris)
      return render json: error, status: :bad_request if error

      application = Doorkeeper::Application.new(
        name: client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes: Doorkeeper.config.default_scopes.to_s,
        confidential: confidential?
      )

      # A public client holds no secret. Doorkeeper generates one regardless, so
      # it is cleared rather than handed out, and PKCE is what proves the client
      # on the token request.
      application.secret = nil unless confidential?

      if application.save
        render json: registration_response(application), status: :created
      else
        render json: {
          error: "invalid_client_metadata",
          error_description: application.errors.full_messages.to_sentence
        }, status: :bad_request
      end
    end

    private

    def validate(redirect_uris)
      if redirect_uris.empty?
        return { error: "invalid_redirect_uri", error_description: "redirect_uris is required" }
      end

      if redirect_uris.size > MAX_REDIRECT_URIS
        return { error: "invalid_redirect_uri", error_description: "At most #{MAX_REDIRECT_URIS} redirect URIs" }
      end

      invalid = redirect_uris.reject { |uri| valid_redirect_uri?(uri) }
      if invalid.any?
        return {
          error: "invalid_redirect_uri",
          error_description: "Redirect URIs must be https, or http on loopback: #{invalid.join(', ')}"
        }
      end

      requested_grants = Array(params[:grant_types]).map(&:to_s)
      if requested_grants.any? && (requested_grants - SUPPORTED_GRANT_TYPES).any?
        return {
          error: "invalid_client_metadata",
          error_description: "Supported grant types: #{SUPPORTED_GRANT_TYPES.join(', ')}"
        }
      end

      requested_responses = Array(params[:response_types]).map(&:to_s)
      if requested_responses.any? && (requested_responses - SUPPORTED_RESPONSE_TYPES).any?
        return {
          error: "invalid_client_metadata",
          error_description: "Supported response types: #{SUPPORTED_RESPONSE_TYPES.join(', ')}"
        }
      end

      nil
    end

    # The MCP spec allows loopback HTTP so a local client can catch its callback;
    # everything else has to be HTTPS.
    def valid_redirect_uri?(uri)
      parsed = URI.parse(uri)
      return false if parsed.fragment.present?
      return true if parsed.is_a?(URI::HTTPS)
      return true if parsed.is_a?(URI::HTTP) && %w[localhost 127.0.0.1 ::1].include?(parsed.host)

      false
    rescue URI::InvalidURIError
      false
    end

    def confidential?
      params[:token_endpoint_auth_method].present? && params[:token_endpoint_auth_method] != "none"
    end

    def client_name
      params[:client_name].presence&.to_s&.truncate(100) || "MCP client"
    end

    def registration_response(application)
      {
        client_id: application.uid,
        client_id_issued_at: application.created_at.to_i,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split("\n"),
        grant_types: SUPPORTED_GRANT_TYPES,
        response_types: SUPPORTED_RESPONSE_TYPES,
        scope: application.scopes.to_s,
        token_endpoint_auth_method: confidential? ? "client_secret_basic" : "none"
      }.tap do |body|
        if confidential?
          body[:client_secret] = application.plaintext_secret
          # 0 means the secret does not expire, per RFC 7591.
          body[:client_secret_expires_at] = 0
        end
      end
    end
  end
end
