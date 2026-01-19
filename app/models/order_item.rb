class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product_lookup, optional: true

  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  def commodity_code_confirmed?
    confirmed_commodity_code.present?
  end

  def display_commodity_code
    confirmed_commodity_code || suggested_commodity_code
  end

  def enhanced_description
    scraped_description.presence || description
  end
end
