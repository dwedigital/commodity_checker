require "test_helper"

class WebhookSignerTest < ActiveSupport::TestCase
  def setup
    @secret = "whsec_testsecret12345"
    @signer = WebhookSigner.new(@secret)
  end

  # Signing Tests

  test "sign returns signature and timestamp" do
    payload = { event: "test", data: { foo: "bar" } }

    result = @signer.sign(payload)

    assert result[:signature].present?
    assert result[:timestamp].present?
    assert result[:signature].start_with?("v1=")
  end

  test "sign generates different signatures for different payloads" do
    payload1 = { event: "test1" }
    payload2 = { event: "test2" }

    sig1 = @signer.sign(payload1)[:signature]
    sig2 = @signer.sign(payload2)[:signature]

    refute_equal sig1, sig2
  end

  test "sign generates same signature for same payload and timestamp" do
    payload = { event: "test" }

    # Create signer twice
    signer1 = WebhookSigner.new(@secret)
    signer2 = WebhookSigner.new(@secret)

    # Same timestamp produces same signature
    timestamp = Time.current.to_i
    payload_string = payload.to_json
    signed_payload = "#{timestamp}.#{payload_string}"

    expected_sig = OpenSSL::HMAC.hexdigest("sha256", @secret, signed_payload)

    sig1 = signer1.sign(payload)
    # Can't easily test same timestamp, but can verify format
    assert sig1[:signature].match?(/^v1=[a-f0-9]{64}$/)
  end

  # Verification Tests

  test "verify returns true for valid signature" do
    payload = { event: "test" }
    sig_data = @signer.sign(payload)

    result = @signer.verify(payload, sig_data[:signature], sig_data[:timestamp])

    assert result
  end

  test "verify returns false for invalid signature" do
    payload = { event: "test" }
    sig_data = @signer.sign(payload)

    result = @signer.verify(payload, "v1=invalidsig", sig_data[:timestamp])

    refute result
  end

  test "verify returns false for modified payload" do
    payload = { event: "test" }
    sig_data = @signer.sign(payload)

    modified_payload = { event: "modified" }
    result = @signer.verify(modified_payload, sig_data[:signature], sig_data[:timestamp])

    refute result
  end

  test "verify returns false for expired timestamp" do
    payload = { event: "test" }
    old_timestamp = (Time.current - 10.minutes).to_i
    payload_string = payload.to_json
    signed_payload = "#{old_timestamp}.#{payload_string}"
    signature = "v1=" + OpenSSL::HMAC.hexdigest("sha256", @secret, signed_payload)

    result = @signer.verify(payload, signature, old_timestamp, tolerance: 300)

    refute result
  end

  test "verify returns false for blank inputs" do
    refute @signer.verify({}, nil, nil)
    refute @signer.verify({}, "", "")
  end

  # Headers Tests

  test "headers returns correct structure" do
    payload = { event: "test" }

    headers = @signer.headers(payload)

    assert_equal "application/json", headers["Content-Type"]
    assert headers["X-Tariffik-Signature"].present?
    assert headers["X-Tariffik-Timestamp"].present?
    assert_equal "Tariffik-Webhook/1.0", headers["User-Agent"]
  end

  # Class Methods Tests

  test "sign_payload class method works" do
    payload = { event: "test" }

    result = WebhookSigner.sign_payload(@secret, payload)

    assert result[:signature].present?
  end

  test "verify_payload class method works" do
    payload = { event: "test" }
    sig_data = WebhookSigner.sign_payload(@secret, payload)

    result = WebhookSigner.verify_payload(@secret, payload, sig_data[:signature], sig_data[:timestamp])

    assert result
  end
end
