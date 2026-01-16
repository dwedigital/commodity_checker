class CreateGuestLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_lookups do |t|
      t.string :guest_token, null: false
      t.string :lookup_type, null: false  # 'url' or 'photo'
      t.text :url
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :guest_lookups, :guest_token
    add_index :guest_lookups, :created_at
    add_index :guest_lookups, [:guest_token, :created_at]
  end
end
