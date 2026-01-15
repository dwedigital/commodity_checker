class OrderItem < ApplicationRecord
  belongs_to :order

  validates :description, presence: true

  def commodity_code_confirmed?
    confirmed_commodity_code.present?
  end

  def display_commodity_code
    confirmed_commodity_code || suggested_commodity_code
  end
end
