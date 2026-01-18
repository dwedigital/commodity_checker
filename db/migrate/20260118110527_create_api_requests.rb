class CreateApiRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :api_requests do |t|
      t.references :api_key, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :method
      t.integer :status_code
      t.integer :response_time_ms
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :api_requests, :created_at
    add_index :api_requests, [ :api_key_id, :created_at ]
  end
end
