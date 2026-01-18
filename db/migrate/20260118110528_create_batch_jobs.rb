class CreateBatchJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_jobs do |t|
      t.references :api_key, null: false, foreign_key: true
      t.string :public_id, null: false
      t.integer :status, default: 0, null: false
      t.integer :total_items, default: 0, null: false
      t.integer :completed_items, default: 0, null: false
      t.integer :failed_items, default: 0, null: false
      t.string :webhook_url
      t.datetime :completed_at

      t.timestamps
    end

    add_index :batch_jobs, :public_id, unique: true
    add_index :batch_jobs, [ :api_key_id, :status ]
  end
end
