class CreateExtensionTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :extension_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :extension_id
      t.string :name
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :extension_tokens, :token_digest, unique: true
    add_index :extension_tokens, :token_prefix
    add_index :extension_tokens, [ :user_id, :revoked_at ]
  end
end
