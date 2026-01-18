class CreateExtensionLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :extension_lookups do |t|
      t.string :extension_id, null: false
      t.string :lookup_type, default: "url"
      t.text :url
      t.string :commodity_code
      t.string :ip_address
      t.timestamps
    end

    add_index :extension_lookups, :extension_id
    add_index :extension_lookups, [ :extension_id, :created_at ]
  end
end
