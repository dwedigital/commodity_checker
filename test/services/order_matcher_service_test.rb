# frozen_string_literal: true

require "test_helper"

class OrderMatcherServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  # =============================================================================
  # Match by Order Reference
  # =============================================================================

  test "matches order by exact order reference" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-12345",
      retailer_name: "Test Retailer"
    )

    parsed_data = { order_reference: "ORD-12345", tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order, matcher.find_matching_order
  end

  test "does not match order reference from different user" do
    other_user = users(:two)
    Order.create!(
      user: other_user,
      order_reference: "ORD-OTHER",
      retailer_name: "Test Retailer"
    )

    parsed_data = { order_reference: "ORD-OTHER", tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "returns nil when order reference not found" do
    parsed_data = { order_reference: "NONEXISTENT-123", tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "returns nil when order reference is blank" do
    Order.create!(
      user: @user,
      order_reference: "ORD-12345",
      retailer_name: "Test Retailer"
    )

    parsed_data = { order_reference: "", tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  # =============================================================================
  # Match by Tracking URL
  # =============================================================================

  test "matches order by tracking URL" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-TRACK-1",
      retailer_name: "Test Retailer"
    )
    TrackingEvent.create!(
      order: order,
      carrier: "royal_mail",
      tracking_url: "https://www.royalmail.com/track?id=ABC123"
    )

    parsed_data = {
      order_reference: nil,
      tracking_urls: [ { carrier: "royal_mail", url: "https://www.royalmail.com/track?id=ABC123" } ],
      retailer_name: nil
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order, matcher.find_matching_order
  end

  test "matches order when one of multiple tracking URLs matches" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-MULTI-TRACK",
      retailer_name: "Test Retailer"
    )
    TrackingEvent.create!(
      order: order,
      carrier: "dhl",
      tracking_url: "https://www.dhl.com/track?id=DHL456"
    )

    parsed_data = {
      order_reference: nil,
      tracking_urls: [
        { carrier: "royal_mail", url: "https://www.royalmail.com/track?id=NEW" },
        { carrier: "dhl", url: "https://www.dhl.com/track?id=DHL456" }
      ],
      retailer_name: nil
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order, matcher.find_matching_order
  end

  test "does not match tracking URL from different user" do
    other_user = users(:two)
    other_order = Order.create!(
      user: other_user,
      order_reference: "ORD-OTHER-TRACK",
      retailer_name: "Test Retailer"
    )
    TrackingEvent.create!(
      order: other_order,
      carrier: "ups",
      tracking_url: "https://www.ups.com/track?id=UPS789"
    )

    parsed_data = {
      order_reference: nil,
      tracking_urls: [ { carrier: "ups", url: "https://www.ups.com/track?id=UPS789" } ],
      retailer_name: nil
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "returns nil when no tracking URLs provided" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-HAS-TRACK",
      retailer_name: "Test Retailer"
    )
    TrackingEvent.create!(
      order: order,
      carrier: "fedex",
      tracking_url: "https://www.fedex.com/track?id=FX123"
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  # =============================================================================
  # Match by Retailer and Timeframe
  # =============================================================================

  test "matches recent order from same retailer without tracking" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-RECENT",
      retailer_name: "Amazon",
      created_at: 2.days.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "Amazon" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order, matcher.find_matching_order
  end

  test "does not match order older than 7 days" do
    Order.create!(
      user: @user,
      order_reference: "ORD-OLD",
      retailer_name: "Amazon",
      created_at: 10.days.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "Amazon" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "does not match order that already has tracking" do
    order = Order.create!(
      user: @user,
      order_reference: "ORD-ALREADY-TRACKED",
      retailer_name: "ASOS",
      created_at: 2.days.ago
    )
    TrackingEvent.create!(
      order: order,
      carrier: "evri",
      tracking_url: "https://www.evri.com/track?id=EV123"
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "ASOS" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "matches most recent order when multiple match retailer" do
    older_order = Order.create!(
      user: @user,
      order_reference: "ORD-OLDER",
      retailer_name: "John Lewis",
      created_at: 5.days.ago
    )
    newer_order = Order.create!(
      user: @user,
      order_reference: "ORD-NEWER",
      retailer_name: "John Lewis",
      created_at: 1.day.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "John Lewis" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal newer_order, matcher.find_matching_order
  end

  test "does not match different retailer" do
    Order.create!(
      user: @user,
      order_reference: "ORD-WRONG-RETAILER",
      retailer_name: "Currys",
      created_at: 2.days.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "Argos" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "returns nil when retailer name is blank" do
    Order.create!(
      user: @user,
      order_reference: "ORD-NO-RETAILER-MATCH",
      retailer_name: "Some Shop",
      created_at: 2.days.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: "" }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  # =============================================================================
  # Matching Priority
  # =============================================================================

  test "order reference takes priority over tracking URL" do
    order_by_ref = Order.create!(
      user: @user,
      order_reference: "ORD-BY-REF",
      retailer_name: "Shop A"
    )

    order_by_track = Order.create!(
      user: @user,
      order_reference: "ORD-BY-TRACK",
      retailer_name: "Shop B"
    )
    TrackingEvent.create!(
      order: order_by_track,
      carrier: "dpd",
      tracking_url: "https://track.dpd.co.uk/track?id=DPD123"
    )

    parsed_data = {
      order_reference: "ORD-BY-REF",
      tracking_urls: [ { carrier: "dpd", url: "https://track.dpd.co.uk/track?id=DPD123" } ],
      retailer_name: "Shop C"
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order_by_ref, matcher.find_matching_order
  end

  test "tracking URL takes priority over retailer timeframe" do
    order_by_track = Order.create!(
      user: @user,
      order_reference: "ORD-TRACK-PRIORITY",
      retailer_name: "Test Shop",
      created_at: 5.days.ago
    )
    TrackingEvent.create!(
      order: order_by_track,
      carrier: "yodel",
      tracking_url: "https://www.yodel.co.uk/track?id=YDL123"
    )

    order_by_retailer = Order.create!(
      user: @user,
      order_reference: "ORD-RETAILER-PRIORITY",
      retailer_name: "Test Shop",
      created_at: 1.day.ago
    )

    parsed_data = {
      order_reference: nil,
      tracking_urls: [ { carrier: "yodel", url: "https://www.yodel.co.uk/track?id=YDL123" } ],
      retailer_name: "Test Shop"
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_equal order_by_track, matcher.find_matching_order
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  test "returns nil when no matching criteria provided" do
    Order.create!(
      user: @user,
      order_reference: "ORD-ORPHAN",
      retailer_name: "Orphan Shop",
      created_at: 2.days.ago
    )

    parsed_data = { order_reference: nil, tracking_urls: [], retailer_name: nil }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end

  test "handles user with no orders" do
    # Ensure user has no orders
    @user.orders.destroy_all

    parsed_data = {
      order_reference: "ORD-123",
      tracking_urls: [ { carrier: "dhl", url: "https://dhl.com/track" } ],
      retailer_name: "Some Shop"
    }
    matcher = OrderMatcherService.new(@user, parsed_data)

    assert_nil matcher.find_matching_order
  end
end
