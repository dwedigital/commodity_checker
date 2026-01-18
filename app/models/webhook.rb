class Webhook < ApplicationRecord
  belongs_to :user

  SUPPORTED_EVENTS = %w[
    batch.completed
    batch.failed
    suggestion.completed
  ].freeze

  MAX_FAILURES = 5

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :secret, presence: true
  validate :validate_events

  serialize :events, coder: JSON

  before_validation :generate_secret, on: :create
  before_validation :normalize_events

  scope :active, -> { where(enabled: true) }
  scope :for_event, ->(event) { active.where("events LIKE ?", "%#{event}%") }

  def self.for_user_event(user, event)
    user.webhooks.active.select { |w| w.subscribed_to?(event) }
  end

  def subscribed_to?(event)
    events.blank? || events.include?(event)
  end

  def record_success!
    update!(
      failure_count: 0,
      last_success_at: Time.current
    )
  end

  def record_failure!
    new_count = failure_count + 1
    update!(
      failure_count: new_count,
      last_failure_at: Time.current,
      enabled: new_count < MAX_FAILURES
    )
  end

  def disabled_due_to_failures?
    !enabled && failure_count >= MAX_FAILURES
  end

  def to_api_hash
    {
      id: id,
      url: url,
      events: events.presence || SUPPORTED_EVENTS,
      enabled: enabled,
      failure_count: failure_count,
      last_success_at: last_success_at&.iso8601,
      created_at: created_at.iso8601
    }
  end

  private

  def generate_secret
    return if secret.present?
    self.secret = "whsec_#{SecureRandom.hex(24)}"
  end

  def normalize_events
    self.events = events&.select { |e| SUPPORTED_EVENTS.include?(e) }
    self.events = nil if events&.empty?
  end

  def validate_events
    return if events.blank?

    invalid_events = events - SUPPORTED_EVENTS
    if invalid_events.any?
      errors.add(:events, "contains invalid events: #{invalid_events.join(', ')}")
    end
  end
end
