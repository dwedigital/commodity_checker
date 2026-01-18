class ApiBatchItemJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(batch_job_item_id)
    item = BatchJobItem.find(batch_job_item_id)
    return if item.completed? || item.failed?

    item.update!(status: :processing)

    service = ApiCommodityService.new

    result = if item.url?
               service.suggest_from_url(item.url)
    else
               service.suggest_from_description(item.description)
    end

    if result[:error]
      item.mark_failed!(result[:error])
    else
      item.mark_completed!(result)
    end

    # Check if batch is complete and trigger webhook
    check_batch_completion(item.batch_job)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("ApiBatchItemJob: BatchJobItem #{batch_job_item_id} not found")
  rescue => e
    Rails.logger.error("ApiBatchItemJob error for item #{batch_job_item_id}: #{e.message}")

    item = BatchJobItem.find_by(id: batch_job_item_id)
    item&.mark_failed!(e.message)

    raise
  end

  private

  def check_batch_completion(batch_job)
    return unless batch_job.completed?

    # Trigger webhook if configured
    if batch_job.webhook_url.present?
      deliver_webhook(batch_job)
    end
  end

  def deliver_webhook(batch_job)
    # Find or create a temporary webhook for this delivery
    user = batch_job.api_key.user

    payload = {
      event: "batch.completed",
      batch_id: batch_job.public_id,
      timestamp: Time.current.iso8601,
      data: {
        total: batch_job.total_items,
        successful: batch_job.completed_items,
        failed: batch_job.failed_items,
        results: batch_job.results
      }
    }

    WebhookDeliveryJob.perform_later(
      nil, # No webhook model, use URL directly
      "batch.completed",
      payload,
      batch_job.webhook_url,
      generate_temp_secret(batch_job)
    )
  end

  def generate_temp_secret(batch_job)
    # Generate a deterministic secret for ad-hoc webhooks
    # Based on API key and batch job for consistency
    Digest::SHA256.hexdigest("#{batch_job.api_key.key_digest}:#{batch_job.public_id}")
  end
end
