class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :orders, dependent: :destroy
  has_many :inbound_emails, dependent: :destroy
  has_many :product_lookups, dependent: :destroy

  before_create :generate_inbound_email_token

  def inbound_email_address
    "track-#{inbound_email_token}@#{Rails.application.config.inbound_email_domain}"
  end

  private

  def generate_inbound_email_token
    self.inbound_email_token = SecureRandom.hex(8)
  end
end
