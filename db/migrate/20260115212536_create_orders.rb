class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :source_email_id
      t.string :order_reference
      t.string :retailer_name
      t.integer :status
      t.date :estimated_delivery

      t.timestamps
    end
  end
end
