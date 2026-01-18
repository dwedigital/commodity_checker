require "test_helper"

class ExtensionTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "generates token on create" do
    token = @user.extension_tokens.create!(name: "Test Token")

    assert token.raw_token.present?
    assert token.raw_token.start_with?("ext_tk_test_")  # test environment prefix
    assert token.token_digest.present?
    assert token.token_prefix.present?
  end

  test "raw_token is only available immediately after create" do
    token = @user.extension_tokens.create!(name: "Test Token")
    raw_token = token.raw_token

    # Reload from database
    token.reload

    assert_nil token.raw_token
    assert token.token_digest.present?
  end

  test "authenticate returns token for valid raw token" do
    token = @user.extension_tokens.create!(name: "Test Token")
    raw_token = token.raw_token

    authenticated = ExtensionToken.authenticate(raw_token)

    assert_equal token.id, authenticated.id
  end

  test "authenticate returns nil for invalid token" do
    assert_nil ExtensionToken.authenticate("ext_tk_live_invalid")
    assert_nil ExtensionToken.authenticate("")
    assert_nil ExtensionToken.authenticate(nil)
  end

  test "authenticate returns nil for revoked token" do
    token = @user.extension_tokens.create!(name: "Test Token")
    raw_token = token.raw_token
    token.revoke!

    assert_nil ExtensionToken.authenticate(raw_token)
  end

  test "revoke! sets revoked_at" do
    token = @user.extension_tokens.create!(name: "Test Token")

    assert_nil token.revoked_at
    token.revoke!
    assert token.revoked_at.present?
  end

  test "revoked? returns correct status" do
    token = @user.extension_tokens.create!(name: "Test Token")

    refute token.revoked?
    token.revoke!
    assert token.revoked?
  end

  test "touch_last_used! updates timestamp" do
    token = @user.extension_tokens.create!(name: "Test Token")

    assert_nil token.last_used_at
    token.touch_last_used!
    assert token.last_used_at.present?
  end

  test "active scope excludes revoked tokens" do
    active_token = @user.extension_tokens.create!(name: "Active")
    revoked_token = @user.extension_tokens.create!(name: "Revoked")
    revoked_token.revoke!

    active_tokens = @user.extension_tokens.active

    assert_includes active_tokens, active_token
    refute_includes active_tokens, revoked_token
  end
end
