class WebhookSigner
  SIGNATURE_HEADER = "X-Tariffik-Signature".freeze
  TIMESTAMP_HEADER = "X-Tariffik-Timestamp".freeze
  SIGNATURE_VERSION = "v1".freeze

  def initialize(secret)
    @secret = secret
  end

  # Generate signature for a payload
  # Returns { signature: "v1=...", timestamp: unix_timestamp }
  def sign(payload)
    timestamp = Time.current.to_i
    payload_string = payload.is_a?(String) ? payload : payload.to_json

    # Create the signed payload: timestamp.payload
    signed_payload = "#{timestamp}.#{payload_string}"

    # Generate HMAC-SHA256 signature
    signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      @secret,
      signed_payload
    )

    {
      signature: "#{SIGNATURE_VERSION}=#{signature}",
      timestamp: timestamp
    }
  end

  # Verify a signature
  # Returns true if valid, false otherwise
  def verify(payload, signature, timestamp, tolerance: 300)
    return false if @secret.blank? || signature.blank? || timestamp.blank?

    # Check timestamp is within tolerance (default 5 minutes)
    timestamp_int = timestamp.to_i
    if (Time.current.to_i - timestamp_int).abs > tolerance
      return false
    end

    # Extract version and signature from header
    match = signature.match(/^(v\d+)=(.+)$/)
    return false unless match

    version = match[1]
    received_sig = match[2]

    return false unless version == SIGNATURE_VERSION

    # Generate expected signature
    payload_string = payload.is_a?(String) ? payload : payload.to_json
    signed_payload = "#{timestamp_int}.#{payload_string}"

    expected_sig = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      @secret,
      signed_payload
    )

    # Use secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(expected_sig, received_sig)
  end

  # Build webhook headers for a payload
  def headers(payload)
    sig_data = sign(payload)

    {
      "Content-Type" => "application/json",
      SIGNATURE_HEADER => sig_data[:signature],
      TIMESTAMP_HEADER => sig_data[:timestamp].to_s,
      "User-Agent" => "Tariffik-Webhook/1.0"
    }
  end

  class << self
    # Convenience method to create a signer and sign
    def sign_payload(secret, payload)
      new(secret).sign(payload)
    end

    # Convenience method to verify
    def verify_payload(secret, payload, signature, timestamp)
      new(secret).verify(payload, signature, timestamp)
    end
  end
end
