# frozen_string_literal: true

# Signing up with an email and password.
#
# Devise sends the confirmation email and holds the account closed until the
# link is clicked; User#email_not_claimed_by_google refuses an address that
# already signs in with Google.
class Users::RegistrationsController < Devise::RegistrationsController
  include Trackable

  def new
    redirect_to dashboard_path and return if user_signed_in?

    session[:signup_source] = params[:source] if params[:source].present?

    super
  end

  protected

  def after_sign_up_path_for(resource)
    track_signup(resource)
    super
  end

  # Where someone lands when the account exists but is not confirmed yet, which
  # is every password signup.
  def after_inactive_sign_up_path_for(resource)
    track_signup(resource, confirmation_pending: true)
    new_user_session_path
  end

  def track_signup(resource, confirmation_pending: false)
    track_event("user_registered", {
      user_id: resource.id,
      registration_source: session.delete(:signup_source) || "password",
      confirmation_pending: confirmation_pending
    })
  end
end
