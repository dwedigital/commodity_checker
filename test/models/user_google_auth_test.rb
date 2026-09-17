require "test_helper"

class UserGoogleAuthTest < ActiveSupport::TestCase
  include OmniauthTestHelper

  test "returns nil when the auth hash is blank" do
    assert_nil User.from_google_omniauth(nil)
  end

  test "returns nil when Google sends no uid" do
    assert_nil User.from_google_omniauth(google_auth_hash(uid: ""))
  end

  test "refuses an unverified email" do
    assert_nil User.from_google_omniauth(google_auth_hash(email_verified: false))
  end

  test "treats a missing email_verified flag as unverified" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "uid-x",
      info: { email: "someone@example.com", name: "Someone" }
    )

    assert_nil User.from_google_omniauth(auth)
  end

  test "stores the Google name and avatar" do
    user = User.from_google_omniauth(google_auth_hash(email: "avatar@example.com", uid: "uid-avatar"))

    assert_equal "New User", user.name
    assert_equal "https://lh3.googleusercontent.com/a/avatar", user.avatar_url
  end

  test "display_name falls back to the email local part" do
    user = User.new(email: "someone@example.com")

    assert_equal "someone", user.display_name
  end

  test "a Google user is created without a password and is confirmed on the spot" do
    user = User.from_google_omniauth(google_auth_hash(email: "fresh@example.com", uid: "uid-fresh"))

    assert_not user.password_set?, "Google sign-up creates no password"
    assert user.confirmed_at.present?, "Google has already verified the address"
    assert user.google_only?
  end

  test "a Google-only account is not asked for a password on save" do
    user = User.from_google_omniauth(google_auth_hash(email: "nopass@example.com", uid: "uid-nopass"))

    assert user.persisted?, user.errors.full_messages.to_sentence
    assert user.valid?
  end
end
