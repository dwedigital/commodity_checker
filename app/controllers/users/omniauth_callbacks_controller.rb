# frozen_string_literal: true

# Handles the return leg of Sign in with Google, the only way into Tariffik.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include Trackable

  # GET|POST /users/auth/google_oauth2/callback
  def google_oauth2
    auth = request.env["omniauth.auth"]
    user = User.from_google_omniauth(auth)

    if user&.persisted?
      track_sign_in(user)
      set_flash_message!(:notice, :success, kind: "Google")
      sign_in_and_redirect(user, event: :authentication)
    else
      redirect_to new_user_session_path, alert: failure_reason(auth, user)
    end
  end

  # OmniAuth routes here when the provider errors or the user cancels.
  def failure
    redirect_to new_user_session_path, alert: "Google sign-in was cancelled or failed. Please try again."
  end

  private

  # A user who existed before this sign-in already had an account; anyone else
  # has just created one. Only the latter is a signup.
  def track_sign_in(user)
    return unless user.previously_new_record?

    track_event("user_registered", {
      user_id: user.id,
      registration_source: session.delete(:signup_source) || "google"
    })
  end

  def failure_reason(auth, user)
    return "Google did not return an email address, so we could not sign you in." if auth&.info&.email.blank?

    if user&.errors&.any?
      "We could not sign you in: #{user.errors.full_messages.to_sentence}."
    else
      "Your Google account's email address is not verified, so we could not sign you in."
    end
  end
end
