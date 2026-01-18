# frozen_string_literal: true

class AddDeviseConfirmableToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmed_at, :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email, :string

    add_index :users, :confirmation_token, unique: true

    # Auto-confirm all existing users to prevent lockout
    # This is safe because existing users have already verified ownership of their email
    # by using the system before confirmation was required
    User.reset_column_information
    User.update_all(confirmed_at: Time.current)
  end

  def down
    remove_index :users, :confirmation_token
    remove_column :users, :unconfirmed_email
    remove_column :users, :confirmation_sent_at
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_token
  end
end
