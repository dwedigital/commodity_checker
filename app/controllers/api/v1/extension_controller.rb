module Api
  module V1
    class ExtensionController < ActionController::API
      before_action :authenticate_extension_token!, only: [ :revoke_token ]
      before_action :set_extension_service

      # POST /api/v1/extension/lookup
      # Perform a commodity code lookup
      # Supports both anonymous (extension_id required) and authenticated (Bearer token) requests
      def lookup
        if authenticated_request?
          authenticated_lookup
        else
          anonymous_lookup
        end
      end

      # GET /api/v1/extension/usage?extension_id=xxx
      # Get usage statistics for anonymous extension
      def usage
        extension_id = params[:extension_id]

        unless extension_id.present?
          return render json: { error: "extension_id is required" }, status: :bad_request
        end

        render json: {
          lookups_used: ExtensionLookup.anonymous_lookups_count(extension_id),
          lookups_remaining: ExtensionLookup.anonymous_lookups_remaining(extension_id),
          limit: ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT,
          type: "anonymous"
        }
      end

      # POST /api/v1/extension/token
      # Exchange an auth code for an extension token
      def exchange_token
        code = params[:code]
        extension_id = params[:extension_id]

        unless code.present? && extension_id.present?
          return render json: { error: "code and extension_id are required" }, status: :bad_request
        end

        token = ExtensionAuthCode.exchange(code, extension_id)

        unless token
          return render json: {
            error: "invalid_code",
            message: "Invalid or expired authorization code"
          }, status: :unauthorized
        end

        render json: {
          token: token.raw_token,
          user: {
            email: token.user.email,
            subscription_tier: token.user.subscription_tier,
            lookups_remaining: token.user.extension_lookups_remaining,
            monthly_limit: token.user.extension_lookup_limit == Float::INFINITY ? "unlimited" : token.user.extension_lookup_limit
          }
        }
      end

      # DELETE /api/v1/extension/token
      # Revoke the current extension token
      def revoke_token
        @current_token.revoke!
        render json: { message: "Token revoked successfully" }
      end

      private

      def set_extension_service
        @extension_service = ExtensionLookupService.new
      end

      def authenticated_request?
        request.headers["Authorization"]&.start_with?("Bearer ext_tk_")
      end

      def authenticate_extension_token!
        auth_header = request.headers["Authorization"]

        unless auth_header&.start_with?("Bearer ")
          return render json: { error: "Missing or invalid authorization header" }, status: :unauthorized
        end

        raw_token = auth_header.split(" ", 2).last
        @current_token = ExtensionToken.authenticate(raw_token)

        unless @current_token
          return render json: { error: "Invalid or revoked token" }, status: :unauthorized
        end

        @current_token.touch_last_used!
        @current_user = @current_token.user
      end

      def anonymous_lookup
        extension_id = params[:extension_id]

        unless extension_id.present?
          return render json: { error: "extension_id is required for anonymous lookups" }, status: :bad_request
        end

        result = @extension_service.anonymous_lookup(
          extension_id: extension_id,
          url: params[:url],
          description: params[:description],
          product: params[:product]&.to_unsafe_h,
          ip_address: request.remote_ip
        )

        if result[:error]
          status = result[:error] == "free_lookups_exhausted" ? :payment_required : :unprocessable_entity
          render json: result, status: status
        else
          render json: result
        end
      end

      def authenticated_lookup
        authenticate_extension_token!
        return if performed?

        result = @extension_service.authenticated_lookup(
          user: @current_user,
          url: params[:url],
          description: params[:description],
          product: params[:product]&.to_unsafe_h,
          save_to_account: params.fetch(:save_to_account, true)
        )

        if result[:error]
          status = result[:error] == "monthly_limit_reached" ? :payment_required : :unprocessable_entity
          render json: result, status: status
        else
          render json: result
        end
      end
    end
  end
end
