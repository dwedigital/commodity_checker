class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :orders, dependent: :destroy
  has_many :inbound_emails, dependent: :destroy
  has_many :product_lookups, dependent: :destroy

  validate :password_strength, if: -> { password.present? }

  before_create :generate_inbound_email_token

  def inbound_email_address
    "track-#{inbound_email_token}@#{Rails.application.config.inbound_email_domain}"
  end

  private

  def generate_inbound_email_token
    self.inbound_email_token = SecureRandom.hex(8)
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
