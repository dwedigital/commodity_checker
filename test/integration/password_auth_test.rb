require "test_helper"

# Email and password alongside Sign in with Google.
class PasswordAuthTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PASSWORD = "Str0ngPassword"

  # Signing up

  test "signing up sends a confirmation email and does not sign you in" do
    assert_difference -> { User.count }, 1 do
      assert_emails 1 do
        sign_up_with(email: "new_person@example.com")
      end
    end

    user = User.find_by(email: "new_person@example.com")
    assert_nil user.confirmed_at, "the account must stay unconfirmed until the link is clicked"
    assert_nil user.provider

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "an unconfirmed account cannot sign in" do
    sign_up_with(email: "unconfirmed@example.com")

    post user_session_path, params: { user: { email: "unconfirmed@example.com", password: PASSWORD } }

    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "clicking the confirmation link opens the account" do
    sign_up_with(email: "confirms@example.com")
    user = User.find_by(email: "confirms@example.com")
    token = user.send(:set_reset_password_token) && nil # keep rubocop quiet about unused
    raw_token = extract_confirmation_token(user)

    get user_confirmation_path(confirmation_token: raw_token)

    assert user.reload.confirmed_at.present?

    post user_session_path, params: { user: { email: "confirms@example.com", password: PASSWORD } }
    get dashboard_path
    assert_response :success
  end

  test "a weak password is refused" do
    assert_no_difference -> { User.count } do
      sign_up_with(email: "weak@example.com", password: "alllowercase")
    end

    assert_match(/uppercase/i, response.body)
  end

  # Google and password on the same address

  test "signing up with an address that already signs in with Google is refused" do
    google_user = users(:one) # fixture carries a google provider and uid

    assert_no_difference -> { User.count } do
      sign_up_with(email: google_user.email)
    end

    assert_match(/already signs in with Google/i, response.body)
  end

  test "signing in with Google on a password account links it and confirms the address" do
    user = User.create!(email: "both@example.com", password: PASSWORD, password_confirmation: PASSWORD)
    user.update_columns(confirmed_at: nil)

    sign_in_with_google google_auth_hash(email: "both@example.com", uid: "uid-both")

    user.reload
    assert_equal "google_oauth2", user.provider
    assert user.password_set?, "the existing password must survive linking"
    assert user.confirmed_at.present?, "Google has verified the address"
  end

  # Password reset

  test "reset works for an account that has a password" do
    User.create!(email: "resets@example.com", password: PASSWORD, password_confirmation: PASSWORD).confirm

    assert_emails 1 do
      post user_password_path, params: { user: { email: "resets@example.com" } }
    end
  end

  test "reset refuses a Google-only account and says why" do
    google_only = users(:two)
    google_only.update_columns(encrypted_password: nil)

    assert_no_emails do
      post user_password_path, params: { user: { email: google_only.email } }
    end

    assert_match(/signs in with Google/i, response.body)
  end

  # Setting a password from account settings

  test "a Google user can set a first password without giving a current one" do
    user = users(:two)
    user.update_columns(encrypted_password: nil)
    sign_in user

    patch account_password_path, params: { user: { password: PASSWORD, password_confirmation: PASSWORD } }

    assert_redirected_to account_path
    assert user.reload.password_set?
    assert user.valid_password?(PASSWORD)
  end

  test "changing an existing password requires the current one" do
    user = User.create!(email: "changer@example.com", password: PASSWORD, password_confirmation: PASSWORD)
    user.confirm
    sign_in user

    patch account_password_path, params: {
      user: { current_password: "WrongPassword1", password: "An0therPassword", password_confirmation: "An0therPassword" }
    }

    assert_response :unprocessable_entity
    assert user.reload.valid_password?(PASSWORD), "the password must not change"
  end

  test "changing a password with the right current one works and keeps you signed in" do
    user = User.create!(email: "changer2@example.com", password: PASSWORD, password_confirmation: PASSWORD)
    user.confirm
    sign_in user

    patch account_password_path, params: {
      user: { current_password: PASSWORD, password: "An0therPassword", password_confirmation: "An0therPassword" }
    }

    assert_redirected_to account_path
    assert user.reload.valid_password?("An0therPassword")

    get dashboard_path
    assert_response :success
  end

  private

  def sign_up_with(email:, password: PASSWORD)
    post user_registration_path, params: {
      user: { email: email, password: password, password_confirmation: password }
    }
  end

  # Devise emails the raw token; the digest is what lands in the column.
  def extract_confirmation_token(user)
    mail = ActionMailer::Base.deliveries.last
    mail.body.encoded[/confirmation_token=([^"&\s]+)/, 1]
  end
end
