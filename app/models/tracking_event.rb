class TrackingEvent < ApplicationRecord
  belongs_to :order

  validates :order_id, presence: true
  validates :carrier, presence: true
  validates :status, presence: true
end
