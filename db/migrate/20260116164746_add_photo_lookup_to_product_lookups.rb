class AddPhotoLookupToProductLookups < ActiveRecord::Migration[8.0]
  def change
    add_column :product_lookups, :lookup_type, :integer, default: 0, null: false
    add_column :product_lookups, :image_description, :text
  end
end
