class AddProductUrlToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :product_url, :string
    add_column :order_items, :scraped_description, :text
    add_reference :order_items, :product_lookup, foreign_key: true
  end
end
