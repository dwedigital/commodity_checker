class Order < ApplicationRecord
  belongs_to :user
  belongs_to :source_email, class_name: "InboundEmail", optional: true

  has_many :order_items, dependent: :destroy
  has_many :tracking_events, dependent: :destroy

  enum :status, { pending: 0, in_transit: 1, delivered: 2 }, default: :pending

  validates :status, presence: true

  def needs_commodity_codes?
    order_items.where(confirmed_commodity_code: nil)
               .where.not(suggested_commodity_code: nil)
               .exists?
  end
end
