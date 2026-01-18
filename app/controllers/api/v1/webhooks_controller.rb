module Api
  module V1
    class WebhooksController < BaseController
      before_action :set_request_start_time
      before_action :find_webhook, only: [ :show, :update, :destroy ]

      # GET /api/v1/webhooks
      # List all webhooks for the user
      def index
        webhooks = current_api_key.user.webhooks

        render_success(
          webhooks: webhooks.map(&:to_api_hash),
          supported_events: Webhook::SUPPORTED_EVENTS
        )
      end

      # GET /api/v1/webhooks/:id
      def show
        render_success(@webhook.to_api_hash.merge(secret: @webhook.secret))
      end

      # POST /api/v1/webhooks
      # Register a new webhook
      def create
        webhook = current_api_key.user.webhooks.build(webhook_params)

        if webhook.save
          render_success(
            webhook.to_api_hash.merge(secret: webhook.secret),
            status: :created
          )
        else
          render_error(:unprocessable_entity, "Failed to create webhook",
                       errors: webhook.errors.full_messages)
        end
      end

      # PATCH /api/v1/webhooks/:id
      def update
        if @webhook.update(webhook_params)
          render_success(@webhook.to_api_hash)
        else
          render_error(:unprocessable_entity, "Failed to update webhook",
                       errors: @webhook.errors.full_messages)
        end
      end

      # DELETE /api/v1/webhooks/:id
      def destroy
        @webhook.destroy
        render_success({ deleted: true })
      end

      # POST /api/v1/webhooks/:id/test
      # Send a test webhook
      def test
        find_webhook

        WebhookDeliveryJob.perform_later(
          @webhook.id,
          "test",
          { message: "This is a test webhook from Tariffik API" }
        )

        render_success({ message: "Test webhook queued for delivery" })
      end

      private

      def find_webhook
        @webhook = current_api_key.user.webhooks.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error(:not_found, "Webhook not found")
      end

      def webhook_params
        params.permit(:url, events: [])
      end
    end
  end
end
