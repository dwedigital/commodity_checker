# Cleans up orphaned inbound emails (where order was deleted)
# Run daily via Solid Queue recurring jobs
class CleanupOrphanedEmailsJob < ApplicationJob
  queue_as :default

  def perform(days_old: 30)
    count = InboundEmail.where(order_id: nil)
                        .where("created_at < ?", days_old.days.ago)
                        .delete_all

    Rails.logger.info("CleanupOrphanedEmailsJob: Deleted #{count} orphaned inbound emails older than #{days_old} days")
  end
end
