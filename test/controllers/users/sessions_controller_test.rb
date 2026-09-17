require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OmniauthTestHelper

  CHROME_ID = "gkjpgbgongkgdjfapjclandjhglnpmpn".freeze
  EXTENSION_CALLBACK = "chrome-extension://#{CHROME_ID}/callback/callback.html".freeze

  test "the sign in page offers Google and nothing else" do
    get new_user_session_path

    assert_response :success
    assert_select "form[action=?]", "/users/auth/google_oauth2"
    assert_select "input[type=password]", count: 0
    assert_select "input[type=email]", count: 0
  end

  # The account page and the navbar both show who you are signed in as, so they
  # render the same partial rather than each deciding what an avatar looks like.
  test "the navbar shows the Google profile photo when there is one" do
    user = users(:one)
    user.update!(avatar_url: "https://lh3.googleusercontent.com/a/photo")
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "img.tf-account-avatar[src=?]", "https://lh3.googleusercontent.com/a/photo"
  end

  test "the navbar falls back to an initial when Google gave no photo" do
    user = users(:one)
    user.update!(avatar_url: nil, name: "Dave Edwards")
    sign_in user

    get dashboard_path

    assert_select "img.tf-account-avatar", count: 0
    assert_select "span.tf-account-avatar", text: "D"
  end

  test "an already signed-in user is sent to their dashboard" do
    sign_in users(:one)

    get new_user_session_path

    assert_redirected_to dashboard_path
  end

  test "signing out ends the session" do
    sign_in users(:one)

    delete destroy_user_session_path
    assert_redirected_to root_path

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "the old password sign-in endpoint no longer exists" do
    post "/users/sign_in", params: { user: { email: users(:one).email, password: "whatever" } }

    assert_response :not_found
  end

  test "the old registration and password-reset pages no longer exist" do
    [ "/users/sign_up", "/users/password/new", "/users/confirmation/new" ].each do |path|
      get path
      assert_response :not_found, "#{path} should be gone"
    end
  end

  # Devise's stored_location_for deletes as it reads. Rendering the sign-in page
  # must not consume the location, or the Google round trip loses it.
  test "sign-in sends you back to the page you were trying to reach" do
    get dashboard_path
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success

    sign_in_with_google(google_auth_hash(email: users(:one).email, uid: "google-uid-one"))
    assert_redirected_to dashboard_path
  end

  test "connecting the extension survives the Google round trip" do
    original = ENV.delete("CHROME_EXTENSION_ID")
    connect = extension_auth_path(extension_id: "ext_abc", redirect_uri: EXTENSION_CALLBACK)

    get connect
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Sign in to connect the extension"

    sign_in_with_google(google_auth_hash(email: users(:one).email, uid: "google-uid-one"))
    assert_redirected_to connect
  ensure
    ENV["CHROME_EXTENSION_ID"] = original if original
  end

  test "an already signed-in user keeps whatever source they arrived with" do
    original = ENV.delete("CHROME_EXTENSION_ID")
    sign_in users(:one)

    get extension_auth_path(extension_id: "ext_abc", redirect_uri: EXTENSION_CALLBACK)

    assert_response :success
    assert_nil session[:signup_source]
  ensure
    ENV["CHROME_EXTENSION_ID"] = original if original
  end

  test "a plain visit to the sign in page keeps the account wording" do
    get new_user_session_path

    assert_response :success
    assert_select "h1", text: "Sign in to Tariffik"
  end
end
