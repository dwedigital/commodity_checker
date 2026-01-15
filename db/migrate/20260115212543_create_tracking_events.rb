class CreateTrackingEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :tracking_events do |t|
      t.references :order, null: false, foreign_key: true
      t.string :carrier
      t.string :tracking_url
      t.string :status
      t.string :location
      t.datetime :event_timestamp
      t.json :raw_data

      t.timestamps
    end
  end
end
