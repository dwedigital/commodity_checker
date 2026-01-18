require "test_helper"

class ExtensionAuthCodeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @extension_id = "ext_#{SecureRandom.uuid}"
  end

  test "generates code on create" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)

    assert auth_code.raw_code.present?
    assert auth_code.raw_code.start_with?("ext_code_")
    assert auth_code.code_digest.present?
  end

  test "sets expiry on create" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)

    assert auth_code.expires_at.present?
    assert auth_code.expires_at > Time.current
    assert auth_code.expires_at <= ExtensionAuthCode::CODE_EXPIRY_MINUTES.minutes.from_now
  end

  test "raw_code is only available immediately after create" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    auth_code.reload

    assert_nil auth_code.raw_code
    assert auth_code.code_digest.present?
  end

  test "exchange returns token for valid code" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    token = ExtensionAuthCode.exchange(raw_code, @extension_id)

    assert token.is_a?(ExtensionToken)
    assert_equal @user.id, token.user_id
    assert_equal @extension_id, token.extension_id
  end

  test "exchange marks code as used" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    ExtensionAuthCode.exchange(raw_code, @extension_id)
    auth_code.reload

    assert auth_code.used_at.present?
  end

  test "exchange returns nil for already used code" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    # First exchange succeeds
    token1 = ExtensionAuthCode.exchange(raw_code, @extension_id)
    assert token1.present?

    # Second exchange fails
    token2 = ExtensionAuthCode.exchange(raw_code, @extension_id)
    assert_nil token2
  end

  test "exchange returns nil for expired code" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    # Manually expire the code
    auth_code.update!(expires_at: 1.minute.ago)

    token = ExtensionAuthCode.exchange(raw_code, @extension_id)
    assert_nil token
  end

  test "exchange returns nil for wrong extension_id" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)
    raw_code = auth_code.raw_code

    token = ExtensionAuthCode.exchange(raw_code, "different_extension_id")
    assert_nil token
  end

  test "exchange returns nil for invalid code" do
    assert_nil ExtensionAuthCode.exchange("ext_code_invalid", @extension_id)
    assert_nil ExtensionAuthCode.exchange("", @extension_id)
    assert_nil ExtensionAuthCode.exchange(nil, @extension_id)
  end

  test "expired? returns correct status" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)

    refute auth_code.expired?

    auth_code.update!(expires_at: 1.minute.ago)
    assert auth_code.expired?
  end

  test "used? returns correct status" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)

    refute auth_code.used?

    auth_code.update!(used_at: Time.current)
    assert auth_code.used?
  end

  test "valid_for_exchange? returns correct status" do
    auth_code = @user.extension_auth_codes.create!(extension_id: @extension_id)

    assert auth_code.valid_for_exchange?

    auth_code.update!(used_at: Time.current)
    refute auth_code.valid_for_exchange?
  end
end
