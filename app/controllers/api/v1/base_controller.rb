module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :set_request_start_time
      before_action :authenticate_api_key!
      before_action :check_rate_limit!
      after_action :log_request
      after_action :increment_usage

      rescue_from StandardError, with: :handle_error
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActionController::ParameterMissing, with: :bad_request

      attr_reader :current_api_key

      protected

      def authenticate_api_key!
        authenticate_with_http_token do |token, _options|
          @current_api_key = ApiKey.authenticate(token)
        end

        unless @current_api_key
          render_error(:unauthorized, "Invalid or missing API key")
        end
      end

      def check_rate_limit!
        return unless current_api_key

        unless current_api_key.within_rate_limit?
          render_error(:too_many_requests, "Daily rate limit exceeded",
                       usage: current_api_key.usage_stats)
        end
      end

      def log_request
        return unless current_api_key
        return if @request_logged

        @request_logged = true
        @response_time_ms = ((Time.current - @request_start_time) * 1000).round if @request_start_time

        ApiRequest.log_request(
          api_key: current_api_key,
          endpoint: request.path,
          method: request.method,
          status_code: response.status,
          response_time_ms: @response_time_ms,
          request: request
        )
      end

      def increment_usage
        return unless current_api_key
        return unless response.successful?
        return if @usage_incremented

        @usage_incremented = true
        current_api_key.increment_usage!
      end

      def render_error(status_sym, message, extra = {})
        render json: {
          error: status_sym.to_s,
          message: message,
          **extra
        }, status: status_sym
      end

      def render_success(data = nil, status: :ok, **extra)
        response_data = if data.is_a?(Hash)
          data
        elsif data.nil? && extra.any?
          extra
        else
          { data: data }
        end

        # Add usage stats to response if API key present
        if current_api_key
          response_data[:usage] = {
            requests_today: current_api_key.requests_today,
            limit_today: current_api_key.requests_per_day_limit
          }
        end

        render json: response_data, status: status
      end

      private

      def handle_error(exception)
        Rails.logger.error("API Error: #{exception.class} - #{exception.message}")
        Rails.logger.error(exception.backtrace.first(10).join("\n"))

        render_error(:internal_server_error, "An unexpected error occurred")
      end

      def not_found(exception)
        render_error(:not_found, exception.message || "Resource not found")
      end

      def bad_request(exception)
        render_error(:bad_request, exception.message)
      end

      def set_request_start_time
        @request_start_time = Time.current
      end
    end
  end
end
