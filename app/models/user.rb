class User < ApplicationRecord
  FREE_MONTHLY_LOOKUP_LIMIT = 5

  # Extension lookup limits by tier (per month)
  EXTENSION_LOOKUP_LIMITS = {
    free: 5,
    starter: 100,
    professional: Float::INFINITY,
    enterprise: Float::INFINITY
  }.freeze

  # Sign in with Google is the only way in. There is no password, so
  # :database_authenticatable, :registerable, :recoverable, :confirmable and
  # :validatable are all gone: Google verifies the address and owns the
  # credential. Session routes are declared by hand in config/routes.rb because
  # Devise only generates them for :database_authenticatable.
  devise :rememberable, :omniauthable, omniauth_providers: [ :google_oauth2 ]

  GOOGLE_PROVIDER = "google_oauth2".freeze

  validates :email, presence: true, uniqueness: { case_sensitive: false }

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

  before_create :generate_inbound_email_token
  after_create :track_account_created

  # Find or create the user behind a Google sign-in.
  #
  # Matching an existing account by email is what carries a user's orders,
  # lookups and API keys across the move off passwords. It is only safe because
  # Google tells us the address is verified — linking on an unverified address
  # would let anyone who can assert an email take over the account, so an
  # unverified one is refused outright.
  def self.from_google_omniauth(auth)
    return nil if auth.blank?

    email = auth.info&.email.to_s.downcase.strip
    uid = auth.uid.to_s
    return nil if email.blank? || uid.blank?
    return nil unless google_email_verified?(auth)

    user = find_by(provider: GOOGLE_PROVIDER, uid: uid) || find_by("LOWER(email) = ?", email)
    return nil if user&.persisted? && user.provider == GOOGLE_PROVIDER && user.uid != uid

    if user
      user.update(google_profile_attributes(auth).merge(email: email))
      user
    else
      create(google_profile_attributes(auth).merge(email: email))
    end
  end

  def self.google_email_verified?(auth)
    verified = auth.info.respond_to?(:email_verified) ? auth.info.email_verified : nil
    verified = auth.extra&.raw_info&.email_verified if verified.nil?

    ActiveModel::Type::Boolean.new.cast(verified) == true
  end
  private_class_method :google_email_verified?

  def self.google_profile_attributes(auth)
    {
      provider: GOOGLE_PROVIDER,
      uid: auth.uid.to_s,
      name: auth.info&.name.presence,
      avatar_url: auth.info&.image.presence
    }.compact
  end
  private_class_method :google_profile_attributes

  def display_name
    name.presence || email.split("@").first
  end

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

  def admin?
    admin == true
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

  # Uses the same count as lookups_this_month since they track the same thing
  alias_method :extension_lookups_this_month, :lookups_this_month

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
end
