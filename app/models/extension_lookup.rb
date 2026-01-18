class ExtensionLookup < ApplicationRecord
  ANONYMOUS_LIFETIME_LIMIT = 3

  validates :extension_id, presence: true
  validates :lookup_type, presence: true

  scope :for_extension, ->(ext_id) { where(extension_id: ext_id) }

  def self.anonymous_lookups_count(extension_id)
    for_extension(extension_id).count
  end

  def self.anonymous_lookups_remaining(extension_id)
    [ ANONYMOUS_LIFETIME_LIMIT - anonymous_lookups_count(extension_id), 0 ].max
  end

  def self.can_perform_anonymous_lookup?(extension_id)
    anonymous_lookups_count(extension_id) < ANONYMOUS_LIFETIME_LIMIT
  end

  def self.record_anonymous_lookup(extension_id:, url:, commodity_code:, ip_address: nil)
    create!(
      extension_id: extension_id,
      lookup_type: url.present? ? "url" : "description",
      url: url,
      commodity_code: commodity_code,
      ip_address: ip_address
    )
  end
end
