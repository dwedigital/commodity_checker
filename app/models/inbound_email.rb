class InboundEmail < ApplicationRecord
  belongs_to :user

  has_one :order, foreign_key: :source_email_id, dependent: :nullify

  enum :processing_status, { received: 0, processing: 1, completed: 2, failed: 3 }, default: :received

  validates :subject, presence: true
  validates :from_address, presence: true
end
