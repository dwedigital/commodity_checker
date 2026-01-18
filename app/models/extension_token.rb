class ExtensionToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true

  before_validation :generate_token, on: :create

  attr_reader :raw_token

  scope :active, -> { where(revoked_at: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_extension, ->(ext_id) { where(extension_id: ext_id) }

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    # Extract prefix from raw token (e.g., "ext_tk_live_abc123..." -> "ext_tk_live_ab")
    prefix = raw_token[0, 15]
    digest = Digest::SHA256.hexdigest(raw_token)

    token = find_by(token_prefix: prefix, token_digest: digest)
    return nil unless token&.active?

    token
  end

  def active?
    revoked_at.nil?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def reload(*args)
    @raw_token = nil
    super
  end

  def touch_last_used!
    touch(:last_used_at)
  end

  def display_token
    return nil unless token_prefix.present?
    "#{token_prefix}...#{token_prefix[-4..]}"
  end

  private

  def generate_token
    return if token_digest.present?

    environment = Rails.env.production? ? "live" : "test"
    random_part = SecureRandom.hex(24)
    @raw_token = "ext_tk_#{environment}_#{random_part}"

    self.token_prefix = @raw_token[0, 15]
    self.token_digest = Digest::SHA256.hexdigest(@raw_token)
  end
end
