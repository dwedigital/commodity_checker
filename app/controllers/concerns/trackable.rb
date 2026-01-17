module Trackable
  extend ActiveSupport::Concern

  private

  def track_event(name, properties = {})
    ahoy.track(name, { user_signed_in: user_signed_in? }.merge(properties))
  rescue => e
    Rails.logger.error("Analytics tracking failed: #{e.message}")
  end
end
