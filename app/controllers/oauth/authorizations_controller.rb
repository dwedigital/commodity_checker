# frozen_string_literal: true

# The OAuth consent screen.
#
# Only exists to widen `form-action` for this one page. The consent form posts
# back here, and the answer is a 302 to the client's registered callback —
# claude.ai, a loopback port for a local MCP client, and so on. Browsers apply
# `form-action` to the whole redirect chain, so under the site-wide
# `form-action 'self'` the browser silently refuses that final hop: the person
# clicks Connect, nothing happens, and nothing is reported anywhere.
#
# Widening it here is safe. The only form on the page posts to this origin, and
# the redirect target is not something the page chooses — Doorkeeper matches it
# exactly against the URIs the client registered and refuses anything else. The
# allowance is narrowed to the origin of that one validated URI rather than
# opening the directive up to every host.
#
# This runs as an after_action, not through the `content_security_policy` DSL:
# that DSL installs a before_action, which is too early — @pre_auth does not
# exist yet, and the allowance would silently come out empty.
module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    after_action :allow_redirect_back_to_client, only: [ :new ]

    private

    def allow_redirect_back_to_client
      origin = client_redirect_origin
      return if origin.blank?

      policy = request.content_security_policy&.clone
      return if policy.nil?

      policy.form_action :self, origin
      request.content_security_policy = policy
    end

    # The origin of the redirect URI Doorkeeper has already validated against
    # the client's registration. Anything unparseable leaves the policy alone.
    def client_redirect_origin
      uri = URI.parse(@pre_auth&.redirect_uri.to_s)
      return nil if uri.host.blank? || uri.scheme.blank?

      port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host}#{port}"
    rescue StandardError
      nil
    end
  end
end
