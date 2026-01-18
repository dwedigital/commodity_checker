class BatchJob < ApplicationRecord
  belongs_to :api_key
  has_many :batch_job_items, dependent: :destroy

  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }

  validates :public_id, presence: true, uniqueness: true

  before_validation :generate_public_id, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :incomplete, -> { where(status: [ :pending, :processing ]) }

  def self.find_by_public_id!(public_id)
    find_by!(public_id: public_id)
  end

  def progress_percentage
    return 0 if total_items.zero?
    ((completed_items + failed_items).to_f / total_items * 100).round(1)
  end

  def estimated_seconds_remaining
    return 0 if completed?

    pending_count = total_items - completed_items - failed_items
    # Estimate ~3 seconds for description, ~8 seconds for URL
    items_by_type = batch_job_items.pending.group(:input_type).count
    description_count = items_by_type["description"] || 0
    url_count = items_by_type["url"] || 0

    (description_count * 3) + (url_count * 8)
  end

  def mark_completed!
    update!(
      status: :completed,
      completed_at: Time.current
    )
  end

  def mark_failed!(error_message = nil)
    update!(
      status: :failed,
      completed_at: Time.current
    )
  end

  def increment_completed!
    with_lock do
      increment!(:completed_items)
      check_completion!
    end
  end

  def increment_failed!
    with_lock do
      increment!(:failed_items)
      check_completion!
    end
  end

  def results
    batch_job_items.includes(:batch_job).map(&:to_result_hash)
  end

  def to_status_hash
    {
      batch_id: public_id,
      status: status,
      total_items: total_items,
      completed_items: completed_items,
      failed_items: failed_items,
      progress_percentage: progress_percentage,
      poll_url: "/api/v1/batch-jobs/#{public_id}",
      webhook_url: webhook_url
    }.tap do |hash|
      hash[:results] = results if completed? || failed?
      hash[:completed_at] = completed_at&.iso8601 if completed_at.present?
    end
  end

  private

  def generate_public_id
    return if public_id.present?
    self.public_id = "batch_#{SecureRandom.alphanumeric(12)}"
  end

  def check_completion!
    if completed_items + failed_items >= total_items
      mark_completed!
    end
  end
end
