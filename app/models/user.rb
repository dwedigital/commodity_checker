class User < ApplicationRecord
  FREE_MONTHLY_LOOKUP_LIMIT = 5

  # Extension lookup limits by tier (per month)
  EXTENSION_LOOKUP_LIMITS = {
    free: 5,
    starter: 100,
    professional: Float::INFINITY,
    enterprise: Float::INFINITY
  }.freeze

  # Two ways in: an email and password, or Sign in with Google. An account can
  # end up with both, but never gets one silently — see the rules below.
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
         :validatable, :confirmable, :omniauthable, omniauth_providers: [ :google_oauth2 ]

  GOOGLE_PROVIDER = "google_oauth2".freeze

  # An email address that already signs in with Google cannot be claimed by a
  # password signup: otherwise knowing someone's address would be enough to
  # attach a credential to their account. They add a password from account
  # settings instead, while signed in. Declared after `devise` so it runs after
  # :validatable's uniqueness check and can replace that generic message.
  validate :email_not_claimed_by_google, on: :create

  validate :password_strength, if: -> { password.present? }

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

  def password_set?
    encrypted_password.present?
  end

  def google_linked?
    provider == GOOGLE_PROVIDER && uid.present?
  end

  # An account that can only get in through Google. Password reset refuses
  # these: sending a link would let anyone holding the inbox set a password and
  # step around whatever protections Google has on the account.
  def google_only?
    google_linked? && !password_set?
  end

  # :validatable insists on a password for every new record. A user created from
  # a Google sign-in has none and never will unless they ask for one.
  def password_required?
    return false if google_linked? && encrypted_password.blank? && password.nil? && password_confirmation.nil?

    super
  end

  # Google has already verified the address, so a Google signup is confirmed on
  # the spot. A password signup still has to click the link in its email.
  def confirmation_required?
    return false if google_linked?

    super
  end

  # Reset is for accounts that actually have a password. A Google-only account
  # gets told to use Google rather than a link that would create one.
  def self.send_reset_password_instructions(attributes = {})
    email = attributes[:email].to_s.downcase.strip
    user = find_by("LOWER(email) = ?", email) if email.present?

    if user&.google_only?
      user.errors.add(:email, :google_only)
      return user
    end

    super
  end

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
      # Linking Google to an existing password account also settles the address:
      # Google has verified it, whether or not they ever clicked our email.
      #
      # skip_reconfirmation! because :reconfirmable would park a changed address
      # in unconfirmed_email and email a link, leaving the account on its old
      # address — when Google has already verified the new one.
      user.skip_reconfirmation!
      user.update(google_profile_attributes(auth)
                    .merge(email: email)
                    .merge(google_confirmation_attributes(user)))
      user
    else
      create(google_profile_attributes(auth)
               .merge(email: email, confirmed_at: Time.current))
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

  # Confirmable would otherwise hold a brand new Google user at the door waiting
  # for an email, when Google has already told us the address is verified.
  def self.google_confirmation_attributes(user)
    user.confirmed_at.present? ? {} : { confirmed_at: Time.current }
  end
  private_class_method :google_confirmation_attributes
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

  def password_strength
    return if password.blank?

    errors.add(:password, "must include at least one uppercase letter") unless password.match?(/[A-Z]/)
    errors.add(:password, "must include at least one lowercase letter") unless password.match?(/[a-z]/)
    errors.add(:password, "must include at least one digit") unless password.match?(/\d/)
  end

  def email_not_claimed_by_google
    return if email.blank?

    existing = User.where.not(id: id).find_by("LOWER(email) = ?", email.downcase.strip)
    return unless existing&.google_linked?

    errors.delete(:email)
    errors.add(:email, :claimed_by_google)
  end

  def track_account_created
    AnalyticsTracker.new(user: self).track("user_account_created", user_id: id)
  rescue => e
    Rails.logger.error("Failed to track account creation: #{e.message}")
  end
end
