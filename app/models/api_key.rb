class ApiKey < ApplicationRecord
  belongs_to :user
  has_many :api_requests, dependent: :destroy
  has_many :batch_jobs, dependent: :destroy

  enum :tier, {
    trial: 0,
    starter: 1,
    professional: 2,
    enterprise: 3
  }

  # Rate limits by tier: { requests_per_minute, requests_per_day, batch_size }
  TIER_LIMITS = {
    trial: { per_minute: 5, per_day: 50, batch_size: 5 },
    starter: { per_minute: 30, per_day: 1_000, batch_size: 25 },
    professional: { per_minute: 100, per_day: 10_000, batch_size: 100 },
    enterprise: { per_minute: 500, per_day: Float::INFINITY, batch_size: 500 }
  }.freeze

  # Tier hierarchy for comparison
  TIER_ORDER = { trial: 0, starter: 1, professional: 2, enterprise: 3 }.freeze

  validates :key_digest, presence: true, uniqueness: true
  validates :key_prefix, presence: true
  validates :tier, presence: true
  validate :user_has_api_access
  validate :tier_within_subscription

  before_validation :generate_key, on: :create
  before_validation :set_default_tier, on: :create

  attr_reader :raw_key

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :for_user, ->(user) { where(user: user) }

  def self.authenticate(raw_key)
    return nil if raw_key.blank?

    # Extract prefix from raw key (e.g., "tk_live_abc123..." -> "tk_live_abc123")
    prefix = raw_key[0, 15]
    digest = Digest::SHA256.hexdigest(raw_key)

    api_key = find_by(key_prefix: prefix, key_digest: digest)
    return nil unless api_key&.active?

    api_key
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def rate_limits
    TIER_LIMITS[tier.to_sym]
  end

  def requests_per_minute_limit
    rate_limits[:per_minute]
  end

  def requests_per_day_limit
    limit = rate_limits[:per_day]
    limit == Float::INFINITY ? nil : limit
  end

  def batch_size_limit
    rate_limits[:batch_size]
  end

  def increment_usage!
    reset_daily_counter_if_needed!

    increment!(:requests_today)
    increment!(:requests_this_month)
    touch(:last_request_at)
  end

  def within_rate_limit?
    return true if requests_per_day_limit.nil?

    reset_daily_counter_if_needed!
    requests_today < requests_per_day_limit
  end

  def usage_stats
    reset_daily_counter_if_needed!

    {
      requests_today: requests_today,
      requests_this_month: requests_this_month,
      limit_today: requests_per_day_limit,
      limit_per_minute: requests_per_minute_limit,
      batch_size_limit: batch_size_limit
    }
  end

  def display_key
    # Show only first and last 4 characters
    return nil unless key_prefix.present?
    "#{key_prefix}...#{key_prefix[-4..]}"
  end

  private

  def generate_key
    return if key_digest.present?

    # Generate a secure random key with prefix
    environment = Rails.env.production? ? "live" : "test"
    random_part = SecureRandom.hex(24)
    @raw_key = "tk_#{environment}_#{random_part}"

    self.key_prefix = @raw_key[0, 15]
    self.key_digest = Digest::SHA256.hexdigest(@raw_key)
  end

  def reset_daily_counter_if_needed!
    if requests_reset_date.nil? || requests_reset_date < Date.current
      update_columns(requests_today: 0, requests_reset_date: Date.current)

      # Also reset monthly if new month
      if requests_reset_date.nil? || requests_reset_date.month != Date.current.month
        update_column(:requests_this_month, 0)
      end
    end
  end

  def user_has_api_access
    return if user.nil?

    unless user.subscription_tier.in?(%w[starter professional enterprise])
      errors.add(:base, "API access requires a Starter subscription or higher")
    end
  end

  def tier_within_subscription
    return if user.nil? || tier.nil?

    user_tier_level = TIER_ORDER[user.subscription_tier.to_sym] || 0
    key_tier_level = TIER_ORDER[tier.to_sym] || 0

    if key_tier_level > user_tier_level
      errors.add(:tier, "cannot exceed your subscription level (#{user.subscription_tier})")
    end
  end

  def set_default_tier
    return if tier.present?

    # Default to user's subscription tier, or starter if higher
    self.tier = user&.subscription_tier || :starter
  end
end
