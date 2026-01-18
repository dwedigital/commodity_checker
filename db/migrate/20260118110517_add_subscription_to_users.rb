class AddSubscriptionToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :subscription_tier, :integer, default: 0, null: false
    add_column :users, :subscription_expires_at, :datetime
  end
end
