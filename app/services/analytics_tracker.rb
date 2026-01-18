class AnalyticsTracker
  def initialize(user: nil)
    @user = user
  end

  def track(name, properties = {})
    # Create event directly in database (works without request context)
    Ahoy::Event.create!(
      user_id: @user&.id,
      name: name,
      properties: properties,
      time: Time.current
    )
  rescue => e
    Rails.logger.error("Analytics tracking failed: #{e.message}")
  end
end
