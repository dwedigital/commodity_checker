class Ahoy::Event < ApplicationRecord
  include Ahoy::QueryMethods

  self.table_name = "ahoy_events"

  belongs_to :visit, optional: true  # Optional for server-side events
  belongs_to :user, optional: true

  serialize :properties, coder: JSON
end
