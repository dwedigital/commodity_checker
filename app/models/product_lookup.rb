class ProductLookup < ApplicationRecord
  belongs_to :user
  belongs_to :order_item, optional: true

  enum :scrape_status, { pending: 0, completed: 1, failed: 2, partial: 3 }

  validates :url, presence: true
  validate :url_format

  def display_description
    parts = [title, description, brand, category, material].compact.reject(&:blank?)
    parts.any? ? parts.join(". ") : url
  end

  def commodity_code_confirmed?
    confirmed_commodity_code.present?
  end

  def display_commodity_code
    confirmed_commodity_code || suggested_commodity_code
  end

  def scraping_complete?
    completed? || failed? || partial?
  end

  def suggestion_ready?
    suggested_commodity_code.present?
  end

  private

  def url_format
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be a valid HTTP or HTTPS URL") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    errors.add(:url, "must be a valid URL")
  end
end
