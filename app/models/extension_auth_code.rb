class ExtensionAuthCode < ApplicationRecord
  CODE_EXPIRY_MINUTES = 5

  belongs_to :user

  validates :code_digest, presence: true, uniqueness: true
  validates :extension_id, presence: true
  validates :expires_at, presence: true

  before_validation :generate_code, on: :create
  before_validation :set_expiry, on: :create

  attr_reader :raw_code

  scope :valid, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.exchange(raw_code, extension_id)
    return nil if raw_code.blank? || extension_id.blank?

    digest = Digest::SHA256.hexdigest(raw_code)
    auth_code = valid.find_by(code_digest: digest, extension_id: extension_id)

    return nil unless auth_code

    # Mark as used
    auth_code.update!(used_at: Time.current)

    # Create and return the extension token
    token = ExtensionToken.create!(
      user: auth_code.user,
      extension_id: extension_id,
      name: "Chrome Extension"
    )

    token
  end

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end

  def valid_for_exchange?
    !expired? && !used?
  end

  def reload(*args)
    @raw_code = nil
    super
  end

  private

  def generate_code
    return if code_digest.present?

    random_part = SecureRandom.hex(32)
    @raw_code = "ext_code_#{random_part}"

    self.code_digest = Digest::SHA256.hexdigest(@raw_code)
  end

  def set_expiry
    self.expires_at ||= CODE_EXPIRY_MINUTES.minutes.from_now
  end
end
