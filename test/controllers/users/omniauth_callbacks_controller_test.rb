require "test_helper"

class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  # Signing up

  test "a new Google account creates a user and signs them in" do
    assert_difference -> { User.count }, 1 do
      sign_in_with_google google_auth_hash(email: "brand_new@example.com", uid: "uid-new")
    end

    user = User.find_by(email: "brand_new@example.com")
    assert_equal "google_oauth2", user.provider
    assert_equal "uid-new", user.uid
    assert_equal "New User", user.name
    assert_redirected_to root_path

    get dashboard_path
    assert_response :success
  end

  test "a new user gets an inbound email token like any other signup" do
    sign_in_with_google google_auth_hash(email: "tokened@example.com", uid: "uid-token")

    assert User.find_by(email: "tokened@example.com").inbound_email_token.present?
  end

  # Linking an existing account

  test "an existing password-era user is matched by email and keeps their data" do
    existing = users(:one)
    existing.update_columns(provider: nil, uid: nil)

    assert_no_difference -> { User.count } do
      sign_in_with_google google_auth_hash(email: existing.email, uid: "uid-linked")
    end

    existing.reload
    assert_equal "google_oauth2", existing.provider
    assert_equal "uid-linked", existing.uid
    assert_redirected_to root_path

    get dashboard_path
    assert_response :success
  end

  test "matching by email ignores case" do
    existing = users(:two)
    existing.update_columns(provider: nil, uid: nil)

    assert_no_difference -> { User.count } do
      sign_in_with_google google_auth_hash(email: existing.email.upcase, uid: "uid-upcase")
    end

    assert_equal "uid-upcase", existing.reload.uid
  end

  test "a returning user is matched on uid even if their Google email changed" do
    existing = users(:one)

    assert_no_difference -> { User.count } do
      sign_in_with_google google_auth_hash(email: "renamed@example.com", uid: existing.uid)
    end

    assert_equal "renamed@example.com", existing.reload.email
  end

  # Refusals

  test "an unverified Google email is refused" do
    # Linking on an unverified address would let anyone asserting an email take
    # over an existing account.
    existing = users(:one)
    existing.update_columns(provider: nil, uid: nil)

    assert_no_difference -> { User.count } do
      sign_in_with_google google_auth_hash(email: existing.email, uid: "uid-attacker", email_verified: false)
    end

    assert_nil existing.reload.provider
    assert_redirected_to new_user_session_path
    assert_match(/not verified/i, flash[:alert])
  end

  test "an account already linked to a different Google uid is refused" do
    existing = users(:one)

    sign_in_with_google google_auth_hash(email: existing.email, uid: "some-other-uid")

    assert_equal "google-uid-one", existing.reload.uid
    assert_redirected_to new_user_session_path
  end

  test "a Google response with no email is refused" do
    assert_no_difference -> { User.count } do
      sign_in_with_google google_auth_hash(email: "", uid: "uid-no-email")
    end

    assert_redirected_to new_user_session_path
    assert_match(/email address/i, flash[:alert])
  end

  test "a cancelled or failed Google sign-in lands back on sign in" do
    stub_omniauth_failure(:access_denied)

    post "/users/auth/google_oauth2"
    follow_redirect!

    assert_redirected_to new_user_session_path
  end
end
