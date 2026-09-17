# frozen_string_literal: true

# Helpers for driving Sign in with Google in tests.
#
# OmniAuth test mode short-circuits the request phase: a POST to
# /users/auth/google_oauth2 redirects straight to the callback with whatever
# auth hash is configured here, so no Google credentials or network are needed.
module OmniauthTestHelper
  GOOGLE_PATH = "/users/auth/google_oauth2"

  def google_auth_hash(email: "new_user@example.com", uid: "google-uid-123", name: "New User",
                       email_verified: true, image: "https://lh3.googleusercontent.com/a/avatar")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, email_verified: email_verified, image: image },
      extra: { raw_info: { email_verified: email_verified } }
    )
  end

  # Walk the whole request -> callback round trip the way a browser would.
  def sign_in_with_google(auth = google_auth_hash)
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    post GOOGLE_PATH
    follow_redirect!
  end

  def stub_omniauth_failure(reason = :invalid_credentials)
    OmniAuth.config.mock_auth[:google_oauth2] = reason
  end
end
