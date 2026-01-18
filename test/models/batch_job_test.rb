require "test_helper"

class BatchJobTest < ActiveSupport::TestCase
  def setup
    @api_key = api_keys(:one)
  end

  # Creation Tests

  test "generates public_id on create" do
    batch_job = @api_key.batch_jobs.create!(total_items: 5)

    assert batch_job.public_id.present?
    assert batch_job.public_id.start_with?("batch_")
  end

  test "starts with pending status" do
    batch_job = @api_key.batch_jobs.create!(total_items: 5)

    assert batch_job.pending?
  end

  # Progress Tests

  test "progress_percentage calculates correctly" do
    batch_job = batch_jobs(:processing)

    # 2 completed + 1 failed out of 5 total = 60%
    assert_equal 60.0, batch_job.progress_percentage
  end

  test "progress_percentage returns 0 for empty batch" do
    batch_job = @api_key.batch_jobs.create!(total_items: 0)

    assert_equal 0, batch_job.progress_percentage
  end

  # Status Methods Tests

  test "mark_completed! updates status and completed_at" do
    batch_job = batch_jobs(:processing)

    batch_job.mark_completed!

    assert batch_job.completed?
    assert batch_job.completed_at.present?
  end

  test "mark_failed! updates status" do
    batch_job = batch_jobs(:processing)

    batch_job.mark_failed!("Test error")

    assert batch_job.failed?
  end

  test "increment_completed! increases counter and checks completion" do
    batch_job = @api_key.batch_jobs.create!(total_items: 1, completed_items: 0, status: :processing)
    batch_job.batch_job_items.create!(input_type: :description, description: "test")

    batch_job.increment_completed!

    batch_job.reload
    assert_equal 1, batch_job.completed_items
    assert batch_job.completed?
  end

  # Find Methods Tests

  test "find_by_public_id! finds by public_id" do
    batch_job = batch_jobs(:one)

    found = BatchJob.find_by_public_id!(batch_job.public_id)

    assert_equal batch_job, found
  end

  test "find_by_public_id! raises for invalid id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      BatchJob.find_by_public_id!("batch_invalid123")
    end
  end

  # Results Tests

  test "to_status_hash returns expected structure" do
    batch_job = batch_jobs(:completed)

    hash = batch_job.to_status_hash

    assert_equal batch_job.public_id, hash[:batch_id]
    assert_equal "completed", hash[:status]
    assert_equal batch_job.total_items, hash[:total_items]
    assert hash.key?(:results)
    assert hash.key?(:poll_url)
  end

  test "to_status_hash excludes results for pending jobs" do
    batch_job = batch_jobs(:one)

    hash = batch_job.to_status_hash

    refute hash.key?(:results)
  end
end
