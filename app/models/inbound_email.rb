class InboundEmail < ApplicationRecord
  belongs_to :user
  belongs_to :order, optional: true

  # Legacy: order created from this email (kept for backwards compatibility)
  has_one :created_order, class_name: "Order", foreign_key: :source_email_id, dependent: :nullify

  enum :processing_status, { received: 0, processing: 1, completed: 2, failed: 3 }, default: :received

  validates :user_id, presence: true
  validates :subject, presence: true
  validates :from_address, presence: true
end
