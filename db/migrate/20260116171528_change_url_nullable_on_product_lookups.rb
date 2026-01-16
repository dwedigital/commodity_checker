class ChangeUrlNullableOnProductLookups < ActiveRecord::Migration[8.0]
  def change
    change_column_null :product_lookups, :url, true
  end
end
