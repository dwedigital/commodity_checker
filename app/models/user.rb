class User < ApplicationRecord
  FREE_MONTHLY_LOOKUP_LIMIT = 5

  # Extension lookup limits by tier (per month)
  EXTENSION_LOOKUP_LIMITS = {
    free: 5,
    starter: 100,
    professional: Float::INFINITY,
    enterprise: Float::INFINITY
  }.freeze

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :orders, dependent: :destroy
  has_many :inbound_emails, dependent: :destroy
  has_many :product_lookups, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :extension_tokens, dependent: :destroy
  has_many :extension_auth_codes, dependent: :destroy

  enum :subscription_tier, {
    free: 0,
    starter: 1,
    professional: 2,
    enterprise: 3
  }

  validate :password_strength, if: -> { password.present? }

  before_create :generate_inbound_email_token
  after_create :track_account_created

  def inbound_email_address
    "track-#{inbound_email_token}@#{Rails.application.config.inbound_email_domain}"
  end

  def subscription_active?
    subscription_expires_at.nil? || subscription_expires_at > Time.current
  end

  def api_tier
    return :trial unless subscription_active?
    subscription_tier.to_sym
  end

  def active_api_keys
    api_keys.active
  end

  def has_api_access?
    subscription_tier.in?(%w[starter professional enterprise]) && subscription_active?
  end

  def premium?
    subscription_tier.in?(%w[starter professional enterprise]) && subscription_active?
  end

  def can_perform_lookup?
    return true unless free?
    lookups_this_month < FREE_MONTHLY_LOOKUP_LIMIT
  end

  def lookups_this_month
    product_lookups.where(created_at: Time.current.beginning_of_month..).count
  end

  def lookups_remaining
    return nil unless free?
    [ FREE_MONTHLY_LOOKUP_LIMIT - lookups_this_month, 0 ].max
  end

  # Extension lookup limits
  def extension_lookup_limit
    EXTENSION_LOOKUP_LIMITS[subscription_tier.to_sym] || EXTENSION_LOOKUP_LIMITS[:free]
  end

  def extension_lookups_this_month
    product_lookups.where(created_at: Time.current.beginning_of_month..).count
  end

  def extension_lookups_remaining
    limit = extension_lookup_limit
    return nil if limit == Float::INFINITY
    [ limit - extension_lookups_this_month, 0 ].max
  end

  def can_perform_extension_lookup?
    limit = extension_lookup_limit
    return true if limit == Float::INFINITY
    extension_lookups_this_month < limit
  end

  def active_extension_tokens
    extension_tokens.active
  end

  private

  def generate_inbound_email_token
    self.inbound_email_token = SecureRandom.hex(8)
  end

  def track_account_created
    AnalyticsTracker.new(user: self).track("user_account_created", user_id: id)
  rescue => e
    Rails.logger.error("Failed to track account creation: #{e.message}")
  end

  def password_strength
    return if password.blank?

    unless password.match?(/[A-Z]/)
      errors.add(:password, "must include at least one uppercase letter")
    end

    unless password.match?(/[a-z]/)
      errors.add(:password, "must include at least one lowercase letter")
    end

    unless password.match?(/\d/)
      errors.add(:password, "must include at least one digit")
    end
  end
end
