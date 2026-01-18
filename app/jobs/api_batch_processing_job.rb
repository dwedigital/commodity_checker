class ApiBatchProcessingJob < ApplicationJob
  queue_as :default

  def perform(batch_job_id)
    batch_job = BatchJob.find(batch_job_id)
    return if batch_job.completed? || batch_job.failed?

    batch_job.update!(status: :processing)

    # Process items in parallel by enqueueing individual jobs
    batch_job.batch_job_items.pending.find_each do |item|
      ApiBatchItemJob.perform_later(item.id)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("ApiBatchProcessingJob: BatchJob #{batch_job_id} not found")
  rescue => e
    Rails.logger.error("ApiBatchProcessingJob error: #{e.message}")
    batch_job&.mark_failed!(e.message)
    raise
  end
end
