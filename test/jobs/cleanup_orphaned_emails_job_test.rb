require "test_helper"

class CleanupOrphanedEmailsJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
  end

  test "deletes orphaned emails older than specified days" do
    # Create an orphaned email (no order) that's old
    old_orphan = InboundEmail.create!(
      user: @user,
      subject: "Old orphan",
      from_address: "test@example.com",
      order_id: nil,
      created_at: 45.days.ago
    )

    # Create an orphaned email that's recent
    recent_orphan = InboundEmail.create!(
      user: @user,
      subject: "Recent orphan",
      from_address: "test@example.com",
      order_id: nil,
      created_at: 5.days.ago
    )

    # Create an email linked to an order (should not be deleted)
    order = Order.create!(user: @user, status: :pending)
    linked_email = InboundEmail.create!(
      user: @user,
      subject: "Linked email",
      from_address: "test@example.com",
      order: order,
      created_at: 45.days.ago
    )

    # Run the job with 30 days threshold
    CleanupOrphanedEmailsJob.perform_now(days_old: 30)

    # Old orphan should be deleted
    assert_not InboundEmail.exists?(old_orphan.id), "Old orphaned email should be deleted"

    # Recent orphan should still exist
    assert InboundEmail.exists?(recent_orphan.id), "Recent orphaned email should not be deleted"

    # Linked email should still exist
    assert InboundEmail.exists?(linked_email.id), "Email linked to order should not be deleted"
  end

  test "does nothing when no orphaned emails exist" do
    initial_count = InboundEmail.count

    CleanupOrphanedEmailsJob.perform_now(days_old: 30)

    assert_equal initial_count, InboundEmail.count
  end
end
