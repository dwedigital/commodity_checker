class ApplicationController < ActionController::Base
  include Trackable

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Track page views for HTML requests
  after_action :track_page_view, if: :trackable_request?

  private

  def track_page_view
    track_event("page_view",
      page: request.path,
      controller: controller_name,
      action: action_name
    )
  rescue => e
    Rails.logger.error("Page view tracking failed: #{e.message}")
  end

  def trackable_request?
    request.format.html? && request.get? && response.successful?
  end
end
