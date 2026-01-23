# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  include Trackable

  protected

  def after_sign_up_path_for(resource)
    track_event("user_registered", {
      user_id: resource.id,
      registration_source: params[:source] || "direct"
    })
    super
  end

  def after_inactive_sign_up_path_for(resource)
    track_event("user_registered", {
      user_id: resource.id,
      registration_source: params[:source] || "direct",
      confirmation_pending: true
    })
    super
  end
end
