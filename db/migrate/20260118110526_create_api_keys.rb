class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key_digest, null: false
      t.string :key_prefix, null: false
      t.string :name
      t.integer :tier, default: 0, null: false
      t.integer :requests_today, default: 0, null: false
      t.integer :requests_this_month, default: 0, null: false
      t.date :requests_reset_date
      t.datetime :last_request_at
      t.datetime :expires_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :key_digest, unique: true
    add_index :api_keys, :key_prefix
    add_index :api_keys, [ :user_id, :revoked_at ]
  end
end
