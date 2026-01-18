require "test_helper"

class ExtensionLookupTest < ActiveSupport::TestCase
  test "records anonymous lookup" do
    extension_id = "ext_#{SecureRandom.uuid}"

    lookup = ExtensionLookup.record_anonymous_lookup(
      extension_id: extension_id,
      url: "https://example.com/product",
      commodity_code: "6109100010",
      ip_address: "127.0.0.1"
    )

    assert lookup.persisted?
    assert_equal extension_id, lookup.extension_id
    assert_equal "https://example.com/product", lookup.url
    assert_equal "6109100010", lookup.commodity_code
    assert_equal "url", lookup.lookup_type
  end

  test "can_perform_anonymous_lookup? returns true when under limit" do
    extension_id = "ext_#{SecureRandom.uuid}"

    assert ExtensionLookup.can_perform_anonymous_lookup?(extension_id)
  end

  test "can_perform_anonymous_lookup? returns false when at limit" do
    extension_id = "ext_#{SecureRandom.uuid}"

    # Create lookups up to the limit
    ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT.times do |i|
      ExtensionLookup.create!(
        extension_id: extension_id,
        url: "https://example.com/product/#{i}",
        commodity_code: "6109100010"
      )
    end

    refute ExtensionLookup.can_perform_anonymous_lookup?(extension_id)
  end

  test "anonymous_lookups_count returns correct count" do
    extension_id = "ext_#{SecureRandom.uuid}"

    2.times do |i|
      ExtensionLookup.create!(
        extension_id: extension_id,
        url: "https://example.com/product/#{i}",
        commodity_code: "6109100010"
      )
    end

    assert_equal 2, ExtensionLookup.anonymous_lookups_count(extension_id)
  end

  test "anonymous_lookups_remaining returns correct count" do
    extension_id = "ext_#{SecureRandom.uuid}"

    2.times do |i|
      ExtensionLookup.create!(
        extension_id: extension_id,
        url: "https://example.com/product/#{i}",
        commodity_code: "6109100010"
      )
    end

    expected_remaining = ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT - 2
    assert_equal expected_remaining, ExtensionLookup.anonymous_lookups_remaining(extension_id)
  end

  test "different extension_ids have separate counts" do
    ext1 = "ext_#{SecureRandom.uuid}"
    ext2 = "ext_#{SecureRandom.uuid}"

    2.times do |i|
      ExtensionLookup.create!(extension_id: ext1, url: "https://a.com/#{i}", commodity_code: "123")
    end

    ExtensionLookup.create!(extension_id: ext2, url: "https://b.com/1", commodity_code: "456")

    assert_equal 2, ExtensionLookup.anonymous_lookups_count(ext1)
    assert_equal 1, ExtensionLookup.anonymous_lookups_count(ext2)
  end
end
