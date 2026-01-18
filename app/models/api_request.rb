class ApiRequest < ApplicationRecord
  belongs_to :api_key

  validates :endpoint, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status_code: 200..299) }
  scope :failed, -> { where.not(status_code: 200..299) }
  scope :today, -> { where("created_at >= ?", Date.current.beginning_of_day) }
  scope :this_month, -> { where("created_at >= ?", Date.current.beginning_of_month) }

  def self.log_request(api_key:, endpoint:, method:, status_code:, response_time_ms:, request:)
    create!(
      api_key: api_key,
      endpoint: endpoint,
      method: method,
      status_code: status_code,
      response_time_ms: response_time_ms,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(255)
    )
  rescue => e
    Rails.logger.error("Failed to log API request: #{e.message}")
  end

  def successful?
    status_code.present? && status_code.between?(200, 299)
  end
end
