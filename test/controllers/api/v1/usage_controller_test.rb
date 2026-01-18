require "test_helper"

class Api::V1::UsageControllerTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  def setup
    @user = users(:one)
    @api_key, @raw_key = create_api_key(user: @user)

    # Create some API requests for testing
    @api_key.api_requests.create!(
      endpoint: "/api/v1/commodity-codes/search",
      method: "GET",
      status_code: 200,
      response_time_ms: 150
    )
    @api_key.api_requests.create!(
      endpoint: "/api/v1/commodity-codes/suggest",
      method: "POST",
      status_code: 200,
      response_time_ms: 3500
    )
  end

  # Show Endpoint Tests

  test "show returns usage statistics" do
    api_get api_v1_usage_path, raw_key: @raw_key

    assert_response :success

    # Check structure
    assert json_response[:api_key].present?
    assert json_response[:limits].present?
    assert json_response[:usage].present?
    assert json_response[:endpoints].present?
    assert json_response[:batch_jobs].present?
  end

  test "show returns correct API key info" do
    api_get api_v1_usage_path, raw_key: @raw_key

    assert_response :success
    assert_equal @api_key.name, json_response[:api_key][:name]
    assert_equal @api_key.tier, json_response[:api_key][:tier]
  end

  test "show returns correct limits" do
    api_get api_v1_usage_path, raw_key: @raw_key

    assert_response :success
    limits = json_response[:limits]
    assert limits[:requests_today].is_a?(Integer)
    assert limits[:limit_today].present?
    assert limits[:limit_per_minute].present?
    assert limits[:batch_size_limit].present?
  end

  test "show returns endpoint breakdown" do
    api_get api_v1_usage_path, raw_key: @raw_key

    assert_response :success
    endpoints = json_response[:endpoints]
    assert endpoints.is_a?(Hash)
  end

  test "show returns batch job counts" do
    @api_key.batch_jobs.create!(total_items: 1, status: :pending)
    @api_key.batch_jobs.create!(total_items: 2, status: :processing)

    api_get api_v1_usage_path, raw_key: @raw_key

    assert_response :success
    batch_jobs = json_response[:batch_jobs]
    assert_equal 2, batch_jobs[:total]
    assert_equal 1, batch_jobs[:pending]
    assert_equal 1, batch_jobs[:processing]
  end

  # History Endpoint Tests

  test "history returns usage over time" do
    api_get api_v1_usage_history_path, raw_key: @raw_key

    assert_response :success
    assert json_response[:days].present?
    assert json_response[:history].is_a?(Array)
  end

  test "history respects days parameter" do
    api_get api_v1_usage_history_path, raw_key: @raw_key, params: { days: 3 }

    assert_response :success
    assert_equal 3, json_response[:days]
    assert_equal 3, json_response[:history].length
  end

  test "history caps days at 30" do
    api_get api_v1_usage_history_path, raw_key: @raw_key, params: { days: 100 }

    assert_response :success
    assert_equal 30, json_response[:days]
  end

  test "history entry has correct structure" do
    api_get api_v1_usage_history_path, raw_key: @raw_key

    assert_response :success
    entry = json_response[:history].first
    assert entry[:date].present?
    assert entry.key?(:total_requests)
    assert entry.key?(:successful_requests)
    assert entry.key?(:failed_requests)
  end
end
