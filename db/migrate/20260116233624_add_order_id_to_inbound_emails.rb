class AddOrderIdToInboundEmails < ActiveRecord::Migration[8.0]
  def change
    add_reference :inbound_emails, :order, null: true, foreign_key: true
  end
end
