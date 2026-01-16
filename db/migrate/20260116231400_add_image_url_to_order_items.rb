class AddImageUrlToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :image_url, :string
  end
end
