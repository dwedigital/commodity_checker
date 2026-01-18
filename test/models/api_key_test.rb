require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  # Key Generation Tests

  test "generates key on create" do
    api_key = @user.api_keys.create!(name: "New Key")

    assert api_key.key_digest.present?
    assert api_key.key_prefix.present?
    assert api_key.raw_key.present?
    assert api_key.raw_key.start_with?("tk_test_")
    assert_equal api_key.raw_key[0, 15], api_key.key_prefix
  end

  test "authenticates with valid key" do
    api_key = @user.api_keys.create!(name: "Auth Test Key")
    raw_key = api_key.raw_key

    found = ApiKey.authenticate(raw_key)

    assert_equal api_key, found
  end

  test "returns nil for invalid key" do
    result = ApiKey.authenticate("tk_test_invalid_key_12345678")

    assert_nil result
  end

  test "returns nil for blank key" do
    assert_nil ApiKey.authenticate(nil)
    assert_nil ApiKey.authenticate("")
  end

  # Active/Revoked Tests

  test "active? returns true for valid key" do
    api_key = api_keys(:one)

    assert api_key.active?
  end

  test "active? returns false for revoked key" do
    api_key = api_keys(:revoked)

    refute api_key.active?
  end

  test "active? returns false for expired key" do
    api_key = api_keys(:one)
    api_key.update!(expires_at: 1.day.ago)

    refute api_key.active?
  end

  test "revoke! sets revoked_at" do
    api_key = api_keys(:one)

    api_key.revoke!

    assert api_key.revoked_at.present?
    refute api_key.active?
  end

  # Rate Limits Tests

  test "returns correct limits for trial tier" do
    api_key = api_keys(:two)  # trial tier

    assert_equal 5, api_key.requests_per_minute_limit
    assert_equal 50, api_key.requests_per_day_limit
    assert_equal 5, api_key.batch_size_limit
  end

  test "returns correct limits for starter tier" do
    api_key = api_keys(:one)  # starter tier

    assert_equal 30, api_key.requests_per_minute_limit
    assert_equal 1_000, api_key.requests_per_day_limit
    assert_equal 25, api_key.batch_size_limit
  end

  test "within_rate_limit? returns true when under limit" do
    api_key = api_keys(:one)
    api_key.update!(requests_today: 10, requests_reset_date: Date.current)

    assert api_key.within_rate_limit?
  end

  test "within_rate_limit? returns false when over limit" do
    api_key = api_keys(:one)
    api_key.update!(requests_today: 1001, requests_reset_date: Date.current)

    refute api_key.within_rate_limit?
  end

  # Usage Tracking Tests

  test "increment_usage! increments counters" do
    api_key = api_keys(:one)
    initial_today = api_key.requests_today
    initial_month = api_key.requests_this_month

    api_key.increment_usage!

    api_key.reload
    assert_equal initial_today + 1, api_key.requests_today
    assert_equal initial_month + 1, api_key.requests_this_month
    assert api_key.last_request_at.present?
  end

  test "resets daily counter when date changes" do
    api_key = api_keys(:one)
    api_key.update!(
      requests_today: 100,
      requests_reset_date: Date.yesterday
    )

    api_key.within_rate_limit?  # This triggers the reset check

    api_key.reload
    assert_equal 0, api_key.requests_today
    assert_equal Date.current, api_key.requests_reset_date
  end

  test "usage_stats returns expected structure" do
    api_key = api_keys(:one)

    stats = api_key.usage_stats

    assert stats.key?(:requests_today)
    assert stats.key?(:requests_this_month)
    assert stats.key?(:limit_today)
    assert stats.key?(:limit_per_minute)
    assert stats.key?(:batch_size_limit)
  end

  # Scopes Tests

  test "active scope excludes revoked keys" do
    active_keys = ApiKey.active

    refute active_keys.include?(api_keys(:revoked))
    assert active_keys.include?(api_keys(:one))
  end
end
