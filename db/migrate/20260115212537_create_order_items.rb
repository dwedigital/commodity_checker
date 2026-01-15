class CreateOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.text :description
      t.integer :quantity
      t.string :suggested_commodity_code
      t.string :confirmed_commodity_code
      t.decimal :commodity_code_confidence
      t.text :llm_reasoning

      t.timestamps
    end
  end
end
