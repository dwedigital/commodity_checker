# frozen_string_literal: true

class ChangeAhoyEventsPropertiesToJsonb < ActiveRecord::Migration[8.0]
  def up
    # Convert properties column from text to jsonb
    # The USING clause handles the conversion of existing data
    change_column :ahoy_events, :properties, :jsonb, using: "properties::jsonb", default: {}

    # Add GIN index for efficient JSON queries
    add_index :ahoy_events, :properties, using: :gin, name: "index_ahoy_events_on_properties_gin"
  end

  def down
    remove_index :ahoy_events, name: "index_ahoy_events_on_properties_gin"
    change_column :ahoy_events, :properties, :text
  end
end
