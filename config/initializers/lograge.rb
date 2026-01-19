Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.base_controller_class = [ "ActionController::Base" ]

  # Add custom data to logs
  config.lograge.custom_options = lambda do |event|
    {
      time: Time.current.iso8601,
      user_id: event.payload[:user_id],
      request_id: event.payload[:request_id],
      ip: event.payload[:ip]
    }.compact
  end
end
