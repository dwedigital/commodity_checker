class ExtensionAuthController < ApplicationController
  # The extension's own callback page (chrome.runtime.getURL("callback/callback.html")).
  # Auth codes are only ever sent here, so a crafted link can't deliver a code to another site.
  CALLBACK_PATH = "/callback/callback.html".freeze
  CHROME_EXTENSION_ID_FORMAT = /\A[a-p]{32}\z/

  # Ahead of authenticate_user!: a signed-out user is about to be sent through
  # Google, and Users::SessionsController only sees a ?source= param when the
  # link carried one. Anyone arriving here came from the extension.
  before_action :remember_extension_signup_source, only: [ :authorize ]
  before_action :authenticate_user!, except: [ :callback ]
  before_action :validate_extension_id, only: [ :authorize, :create_code ]
  before_action :validate_redirect_uri, only: [ :authorize, :create_code ]

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

  def remember_extension_signup_source
    return if user_signed_in?

    session[:signup_source] = "extension"
  end

  def validate_extension_id
    @extension_id = params[:extension_id]

    unless @extension_id.present?
      flash[:alert] = "Invalid authorization request: missing extension ID"
      redirect_to root_path
    end
  end

  # A blank redirect_uri falls back to showing the code for manual copy.
  def validate_redirect_uri
    redirect_uri = params[:redirect_uri]
    return if redirect_uri.blank? || allowed_redirect_uri?(redirect_uri)

    Rails.logger.warn("Rejected extension auth redirect_uri: #{redirect_uri.truncate(200)}")
    flash[:alert] = "Invalid authorization request: this link didn’t come from the Tariffik extension"
    redirect_to root_path
  end

  def allowed_redirect_uri?(redirect_uri)
    uri = URI.parse(redirect_uri)
    return false unless uri.scheme == "chrome-extension" && uri.path == CALLBACK_PATH
    return false if uri.query.present? || uri.fragment.present? || uri.userinfo.present? || uri.port.present?

    allowed_id = ENV["CHROME_EXTENSION_ID"].presence
    # Without a configured ID (development/test) accept any well-formed Chrome extension ID, matching config/initializers/cors.rb.
    allowed_id ? uri.host == allowed_id : uri.host.to_s.match?(CHROME_EXTENSION_ID_FORMAT)
  rescue URI::InvalidURIError
    false
  end
end
