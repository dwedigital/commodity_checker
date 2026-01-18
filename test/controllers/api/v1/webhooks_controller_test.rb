require "test_helper"

class Api::V1::WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  def setup
    @user = users(:one)
    @api_key, @raw_key = create_api_key(user: @user)
    @webhook = @user.webhooks.create!(url: "https://example.com/hook")
  end

  # Index Endpoint Tests

  test "index returns list of webhooks" do
    api_get api_v1_webhooks_path, raw_key: @raw_key

    assert_response :success
    assert json_response[:webhooks].is_a?(Array)
    assert json_response[:supported_events].is_a?(Array)
  end

  test "index includes webhook details" do
    api_get api_v1_webhooks_path, raw_key: @raw_key

    assert_response :success
    webhook = json_response[:webhooks].find { |w| w[:id] == @webhook.id }
    assert webhook.present?
    assert_equal @webhook.url, webhook[:url]
    assert webhook[:enabled]
  end

  # Show Endpoint Tests

  test "show returns webhook details with secret" do
    api_get api_v1_webhook_path(@webhook), raw_key: @raw_key

    assert_response :success
    assert_equal @webhook.id, json_response[:id]
    assert_equal @webhook.url, json_response[:url]
    assert json_response[:secret].present?
  end

  test "show returns 404 for non-existent webhook" do
    api_get api_v1_webhook_path(99999), raw_key: @raw_key

    assert_response :not_found
  end

  test "show returns 404 for webhook belonging to different user" do
    other_user = users(:two)
    other_webhook = other_user.webhooks.create!(url: "https://other.com/hook")
    other_key, other_raw = create_api_key(user: other_user)

    api_get api_v1_webhook_path(other_webhook), raw_key: @raw_key

    assert_response :not_found
  end

  # Create Endpoint Tests

  test "create creates new webhook" do
    api_post api_v1_webhooks_path,
             raw_key: @raw_key,
             params: { url: "https://new.example.com/webhook" }

    assert_response :created
    assert json_response[:id].present?
    assert json_response[:secret].present?
    assert_equal "https://new.example.com/webhook", json_response[:url]
  end

  test "create with events array" do
    api_post api_v1_webhooks_path,
             raw_key: @raw_key,
             params: {
               url: "https://new.example.com/webhook",
               events: [ "batch.completed" ]
             }

    assert_response :created
    assert_includes json_response[:events], "batch.completed"
  end

  test "create returns error for invalid URL" do
    api_post api_v1_webhooks_path,
             raw_key: @raw_key,
             params: { url: "not-a-valid-url" }

    assert_response :unprocessable_entity
    assert json_response[:errors].present?
  end

  # Update Endpoint Tests

  test "update modifies webhook" do
    api_patch api_v1_webhook_path(@webhook),
              raw_key: @raw_key,
              params: { url: "https://updated.example.com/hook" }

    assert_response :success
    assert_equal "https://updated.example.com/hook", json_response[:url]

    @webhook.reload
    assert_equal "https://updated.example.com/hook", @webhook.url
  end

  # Destroy Endpoint Tests

  test "destroy deletes webhook" do
    webhook_id = @webhook.id

    api_delete api_v1_webhook_path(@webhook), raw_key: @raw_key

    assert_response :success
    assert json_response[:deleted]
    refute Webhook.exists?(webhook_id)
  end

  # Test Endpoint Tests

  test "test queues test webhook delivery" do
    assert_enqueued_with(job: WebhookDeliveryJob) do
      api_post test_api_v1_webhook_path(@webhook), raw_key: @raw_key, params: {}
    end

    assert_response :success
    assert_match(/queued/i, json_response[:message])
  end
end
