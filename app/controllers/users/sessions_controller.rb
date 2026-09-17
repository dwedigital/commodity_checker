# frozen_string_literal: true

# Sign in and sign out.
#
# A Devise::SessionsController again now the model carries
# :database_authenticatable, so `create` is Devise's. What is added here is the
# context the page needs and the stored-location handling the Google round trip
# depends on.
class Users::SessionsController < Devise::SessionsController
  # Ahead of Devise's require_no_authentication, which would otherwise send an
  # already signed-in visitor to the root path.
  prepend_before_action :redirect_signed_in_user, only: [ :new, :create ]

  def new
    # Remembered so a signup can be attributed once Google sends us back.
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

    super
  end

  protected

  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end

  private

  def redirect_signed_in_user
    redirect_to dashboard_path if user_signed_in?
  end
end
