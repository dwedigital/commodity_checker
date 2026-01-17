class CreateProductLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :product_lookups do |t|
      t.references :user, null: false, foreign_key: true
      t.references :order_item, foreign_key: true, null: true

      # Input
      t.string :url, null: false
      t.string :retailer_name

      # Scraped data
      t.string :title
      t.text :description
      t.string :brand
      t.string :category
      t.string :price
      t.string :currency
      t.string :material
      t.string :image_url
      t.json :structured_data

      # Status
      t.integer :scrape_status, default: 0
      t.text :scrape_error
      t.datetime :scraped_at

      # Commodity code (for standalone lookups)
      t.string :suggested_commodity_code
      t.decimal :commodity_code_confidence, precision: 5, scale: 4
      t.text :llm_reasoning
      t.string :confirmed_commodity_code

      t.timestamps
    end

    add_index :product_lookups, :url
    add_index :product_lookups, [ :user_id, :created_at ]
  end
end
