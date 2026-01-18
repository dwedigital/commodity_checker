class BatchJobItem < ApplicationRecord
  belongs_to :batch_job

  enum :input_type, {
    description: 0,
    url: 1
  }

  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }

  validates :input_type, presence: true
  validate :has_input

  serialize :scraped_product, coder: JSON

  scope :pending, -> { where(status: :pending) }
  scope :processing, -> { where(status: :processing) }

  def mark_completed!(result)
    update!(
      status: :completed,
      commodity_code: result[:commodity_code],
      confidence: result[:confidence],
      reasoning: result[:reasoning],
      category: result[:category],
      validated: result[:validated],
      scraped_product: result[:scraped_product],
      processed_at: Time.current
    )
    batch_job.increment_completed!
  end

  def mark_failed!(error)
    update!(
      status: :failed,
      error_message: error.to_s.truncate(500),
      processed_at: Time.current
    )
    batch_job.increment_failed!
  end

  def to_result_hash
    base = {
      id: external_id || id.to_s,
      status: status == "completed" ? "success" : status
    }

    if completed?
      base.merge!(
        commodity_code: commodity_code,
        confidence: confidence&.to_f,
        reasoning: reasoning,
        category: category,
        validated: validated
      )
      base[:scraped_product] = scraped_product if scraped_product.present?
    elsif failed?
      base[:error] = error_message
    end

    base
  end

  private

  def has_input
    if description? && description.blank?
      errors.add(:description, "is required for description input type")
    elsif url? && url.blank?
      errors.add(:url, "is required for URL input type")
    end
  end
end
