class AddGoogleIdentityToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :name, :string
    add_column :users, :avatar_url, :string

    add_index :users, [ :provider, :uid ], unique: true

    # Password login is gone, so a user no longer has to carry a hash. Existing
    # hashes are left in place: dropping the password, reset, and confirmation
    # columns is a separate migration to run once Google sign-in is proven in
    # production and there is no reason to roll back.
    change_column_null :users, :encrypted_password, true
    change_column_default :users, :encrypted_password, from: "", to: nil
  end
end
