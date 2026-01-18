class CreateBatchJobItems < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_job_items do |t|
      t.references :batch_job, null: false, foreign_key: true
      t.string :external_id
      t.integer :input_type, default: 0, null: false
      t.text :description
      t.string :url
      t.integer :status, default: 0, null: false
      t.string :commodity_code
      t.decimal :confidence, precision: 4, scale: 2
      t.string :reasoning
      t.string :category
      t.boolean :validated
      t.text :error_message
      t.text :scraped_product
      t.datetime :processed_at

      t.timestamps
    end

    add_index :batch_job_items, [ :batch_job_id, :status ]
  end
end
