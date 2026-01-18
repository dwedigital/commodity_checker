class ExtensionAuthController < ApplicationController
  before_action :authenticate_user!, except: [ :callback ]
  before_action :validate_extension_id, only: [ :authorize, :create_code ]

  # GET /extension/auth
  # Shows authorization page for the extension to request access
  def authorize
    # User is already authenticated via Devise
    # Show them a page to authorize the extension
    @extension_id = params[:extension_id]
    @redirect_uri = params[:redirect_uri]
  end

  # POST /extension/auth
  # Creates an auth code and redirects back to extension
  def create_code
    @extension_id = params[:extension_id]
    redirect_uri = params[:redirect_uri]

    # Create the auth code
    auth_code = current_user.extension_auth_codes.create!(
      extension_id: @extension_id
    )

    # Redirect back to extension with the code
    if redirect_uri.present?
      redirect_to "#{redirect_uri}?code=#{auth_code.raw_code}", allow_other_host: true
    else
      # Fallback: show the code to copy manually
      @auth_code = auth_code.raw_code
      render :callback
    end
  end

  # GET /extension/auth/callback
  # Static callback page that passes the code to the extension
  def callback
    @code = params[:code]
  end

  private

  def validate_extension_id
    @extension_id = params[:extension_id]

    unless @extension_id.present?
      flash[:alert] = "Invalid authorization request: missing extension ID"
      redirect_to root_path
    end
  end
end
