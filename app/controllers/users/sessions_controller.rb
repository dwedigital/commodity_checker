# frozen_string_literal: true

# Sign in and sign out.
#
# Not a Devise::SessionsController: that class exists to accept an email and
# password, which this app no longer has. `new` renders the Google button and
# `destroy` ends the session; the actual authentication happens in
# Users::OmniauthCallbacksController.
class Users::SessionsController < ApplicationController
  def new
    redirect_to dashboard_path and return if user_signed_in?

    # Remembered so the signup can be attributed once Google sends us back.
    session[:signup_source] = params[:source] if params[:source].present?

    # Devise's stored_location_for deletes as it reads, but the Google round
    # trip only gets back here at the callback, long after this page rendered.
    # Put it back, or everyone who was sent here from a protected page lands on
    # the dashboard instead of where they were going. The browser extension
    # feels this hardest: it sends people to /extension/auth for a connection
    # code and there is no other route to that page.
    @after_sign_in = stored_location_for(:user)
    store_location_for(:user, @after_sign_in) if @after_sign_in

    @connecting_extension = @after_sign_in.to_s.start_with?(extension_auth_path)
  end

  def destroy
    sign_out(:user)
    redirect_to root_path, notice: "Signed out."
  end
end
