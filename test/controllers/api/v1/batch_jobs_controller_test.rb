require "test_helper"

class Api::V1::BatchJobsControllerTest < ActionDispatch::IntegrationTest
  include ApiTestHelper

  def setup
    @user = users(:one)
    @api_key, @raw_key = create_api_key(user: @user)

    # Create a batch job for this API key
    @batch_job = @api_key.batch_jobs.create!(
      total_items: 2,
      status: :processing
    )
    @batch_job.batch_job_items.create!(
      input_type: :description,
      description: "Test product",
      status: :completed,
      commodity_code: "6109100010",
      confidence: 0.85
    )
  end

  # Show Endpoint Tests

  test "show returns batch job status" do
    api_get api_v1_batch_job_path(@batch_job.public_id), raw_key: @raw_key

    assert_response :success
    assert_equal @batch_job.public_id, json_response[:batch_id]
    assert_equal "processing", json_response[:status]
    assert_equal 2, json_response[:total_items]
  end

  test "show returns 404 for non-existent batch job" do
    api_get api_v1_batch_job_path("batch_invalid123"), raw_key: @raw_key

    assert_response :not_found
  end

  test "show returns 404 for batch job belonging to different user" do
    other_user = users(:two)
    other_key, other_raw = create_api_key(user: other_user)
    other_batch = other_key.batch_jobs.create!(total_items: 1)

    api_get api_v1_batch_job_path(other_batch.public_id), raw_key: @raw_key

    assert_response :not_found
  end

  test "show includes results for completed batch job" do
    @batch_job.update!(status: :completed, completed_at: Time.current)

    api_get api_v1_batch_job_path(@batch_job.public_id), raw_key: @raw_key

    assert_response :success
    assert json_response[:results].present?
  end

  # Index Endpoint Tests

  test "index returns list of batch jobs" do
    api_get api_v1_batch_jobs_path, raw_key: @raw_key

    assert_response :success
    assert json_response[:batch_jobs].is_a?(Array)
    assert json_response[:total].is_a?(Integer)
  end

  test "index only returns batch jobs for current API key" do
    other_user = users(:two)
    other_key, other_raw = create_api_key(user: other_user)
    other_key.batch_jobs.create!(total_items: 1)

    api_get api_v1_batch_jobs_path, raw_key: @raw_key

    assert_response :success
    batch_ids = json_response[:batch_jobs].map { |b| b[:batch_id] }
    assert batch_ids.include?(@batch_job.public_id)
    refute batch_ids.any? { |id| id.start_with?("batch_") && !@api_key.batch_jobs.exists?(public_id: id) }
  end

  test "index respects limit parameter" do
    # Create additional batch jobs
    3.times { @api_key.batch_jobs.create!(total_items: 1) }

    api_get api_v1_batch_jobs_path, raw_key: @raw_key, params: { limit: 2 }

    assert_response :success
    assert_equal 2, json_response[:batch_jobs].length
  end

  test "index respects offset parameter" do
    api_get api_v1_batch_jobs_path, raw_key: @raw_key, params: { offset: 1 }

    assert_response :success
    # Should have fewer results due to offset
  end
end
