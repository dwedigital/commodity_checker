class CreateInboundEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :inbound_emails do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subject
      t.string :from_address
      t.text :body_text
      t.datetime :processed_at
      t.integer :processing_status

      t.timestamps
    end
  end
end
