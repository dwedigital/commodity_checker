class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks

  # Retry with exponential backoff: 1min, 5min, 25min
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  TIMEOUT = 30 # seconds

  def perform(webhook_id, event, payload, url = nil, secret = nil)
    # Load webhook if ID provided
    if webhook_id.present?
      webhook = Webhook.find(webhook_id)
      return unless webhook.enabled?
      return unless webhook.subscribed_to?(event)

      url = webhook.url
      secret = webhook.secret
    end

    return if url.blank? || secret.blank?

    # Build the full payload
    full_payload = {
      event: event,
      timestamp: Time.current.iso8601,
      data: payload
    }

    # Sign and deliver
    deliver(url, secret, full_payload, webhook)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("WebhookDeliveryJob: Webhook #{webhook_id} not found")
  end

  private

  def deliver(url, secret, payload, webhook = nil)
    signer = WebhookSigner.new(secret)
    headers = signer.headers(payload)

    conn = Faraday.new do |f|
      f.options.timeout = TIMEOUT
      f.options.open_timeout = 10
      f.adapter Faraday.default_adapter
    end

    response = conn.post(url) do |req|
      req.headers = headers
      req.body = payload.to_json
    end

    if response.success?
      Rails.logger.info("Webhook delivered successfully to #{url}")
      webhook&.record_success!
    else
      error = "HTTP #{response.status}: #{response.body.truncate(200)}"
      Rails.logger.warn("Webhook delivery failed to #{url}: #{error}")
      webhook&.record_failure!
      raise StandardError, error
    end
  rescue Faraday::Error => e
    Rails.logger.error("Webhook delivery error to #{url}: #{e.message}")
    webhook&.record_failure!
    raise
  end
end
