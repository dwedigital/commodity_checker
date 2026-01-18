class CreateExtensionAuthCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :extension_auth_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.string :extension_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :extension_auth_codes, :code_digest, unique: true
    add_index :extension_auth_codes, :expires_at
  end
end
