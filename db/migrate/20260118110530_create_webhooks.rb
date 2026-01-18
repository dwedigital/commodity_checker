class CreateWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url, null: false
      t.string :secret, null: false
      t.text :events
      t.boolean :enabled, default: true, null: false
      t.integer :failure_count, default: 0, null: false
      t.datetime :last_success_at
      t.datetime :last_failure_at

      t.timestamps
    end

    add_index :webhooks, [ :user_id, :enabled ]
  end
end
