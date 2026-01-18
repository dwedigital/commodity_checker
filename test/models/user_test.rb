require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @free_user = users(:free_user)
    @starter_user = users(:one)
  end

  # Lookup limit methods tests

  test "FREE_MONTHLY_LOOKUP_LIMIT constant is 5" do
    assert_equal 5, User::FREE_MONTHLY_LOOKUP_LIMIT
  end

  test "lookups_this_month counts only current month lookups" do
    # Clear any existing lookups
    @free_user.product_lookups.destroy_all

    # Create a lookup from last month
    travel_to 1.month.ago do
      @free_user.product_lookups.create!(url: "https://example.com/old", scrape_status: :completed)
    end

    # Create a lookup from this month
    @free_user.product_lookups.create!(url: "https://example.com/new", scrape_status: :completed)

    assert_equal 1, @free_user.lookups_this_month
  end

  test "lookups_remaining returns correct count for free user" do
    @free_user.product_lookups.destroy_all

    assert_equal 5, @free_user.lookups_remaining

    2.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert_equal 3, @free_user.lookups_remaining
  end

  test "lookups_remaining returns 0 when limit exceeded" do
    @free_user.product_lookups.destroy_all

    6.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert_equal 0, @free_user.lookups_remaining
  end

  test "lookups_remaining returns nil for premium users" do
    assert_nil @starter_user.lookups_remaining
  end

  test "can_perform_lookup? returns true for free user under limit" do
    @free_user.product_lookups.destroy_all

    assert @free_user.can_perform_lookup?

    4.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert @free_user.can_perform_lookup?
  end

  test "can_perform_lookup? returns false for free user at limit" do
    @free_user.product_lookups.destroy_all

    5.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    refute @free_user.can_perform_lookup?
  end

  test "can_perform_lookup? returns true for premium users regardless of count" do
    @starter_user.product_lookups.destroy_all

    10.times do |i|
      @starter_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert @starter_user.can_perform_lookup?
  end

  test "premium? returns false for free user" do
    refute @free_user.premium?
  end

  test "premium? returns true for starter user with active subscription" do
    @starter_user.update!(subscription_expires_at: 1.month.from_now)
    assert @starter_user.premium?
  end

  test "premium? returns false for starter user with expired subscription" do
    @starter_user.update!(subscription_expires_at: 1.day.ago)
    refute @starter_user.premium?
  end

  test "lookup limit resets at month boundary" do
    @free_user.product_lookups.destroy_all

    # Create 5 lookups "last month"
    travel_to 1.month.ago do
      5.times do |i|
        @free_user.product_lookups.create!(url: "https://example.com/old_#{i}", scrape_status: :completed)
      end
    end

    # Should have limit available in current month
    assert_equal 5, @free_user.lookups_remaining
    assert @free_user.can_perform_lookup?
  end
end
