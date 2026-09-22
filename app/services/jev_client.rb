# frozen_string_literal: true

# Client for TypeSafe AI's "Jev" decision model (https://api.typesafe.ai).
#
# Jev is a decision model, not a text generator: you send a `state` (free text
# or a JSON object) plus one or more typed `questions`, and it returns typed
# answers with calibrated probabilities. See claude/implementations/jev-chooser.md.
#
# REST: POST https://api.typesafe.ai/v1/systemone, Authorization: Bearer <key>,
# JSON body { model, state, questions }.
class JevClient
  ENDPOINT = "https://api.typesafe.ai/v1/systemone"
  DEFAULT_MODEL = "jev-latest"
  DEFAULT_TIMEOUT = 8
  RETRY_BACKOFF = 0.5 # seconds

  def initialize(api_key: ENV["TYPESAFE_API_KEY"], model: DEFAULT_MODEL, timeout: DEFAULT_TIMEOUT)
    @api_key = api_key
    @model = model
    @timeout = timeout
  end

  # True when an API key is present.
  def configured?
    @api_key.present?
  end

  # Build a `choice` question. `criteria` is a Hash of option key => description
  # (there is no `options` field). Jev returns the chosen key, a confidence and a
  # per-key probabilities map.
  def self.choice(instructions:, criteria:)
    { type: "choice", instructions: instructions, criteria: criteria }
  end

  # Build a `noul` question. Jev returns a single calibrated probability (0..1).
  def self.noul(instructions:)
    { type: "noul", instructions: instructions }
  end

  # Build a `score` question. `levels` is an ordered Array of 2..10 level
  # descriptions; Jev returns a score, legend, probabilities and confidence.
  def self.score(instructions:, levels:)
    { type: "score", instructions: instructions, criteria: levels }
  end

  # Evaluate `state` against `questions`.
  #
  # @param state [String, Hash] free text or a JSON object
  # @param questions [Hash] question id => question hash (see the builders)
  # @return [Hash, nil] the parsed response (`answers`, `usage`, `model`) or nil
  #   on any failure. Never raises. One retry on a timeout, 429 or 5xx.
  def evaluate(state:, questions:)
    unless configured?
      Rails.logger.warn("[jev] TYPESAFE_API_KEY not configured; skipping request")
      return nil
    end

    response = post_with_retry(model: @model, state: state, questions: questions)
    return nil unless response

    if response.success? && response.body.is_a?(Hash)
      log_usage(response.body)
      response.body
    else
      log_failure(response)
      nil
    end
  end

  private

  def post_with_retry(payload)
    attempt = 0

    loop do
      attempt += 1

      begin
        response = connection.post(ENDPOINT) { |req| req.body = payload }
      rescue Faraday::TimeoutError => e
        if attempt == 1
          Rails.logger.warn("[jev] request timed out; retrying once")
          sleep(RETRY_BACKOFF)
          next
        end
        Rails.logger.warn("[jev] request timed out after #{attempt} attempts: #{e.message}")
        return nil
      rescue Faraday::Error => e
        Rails.logger.warn("[jev] request failed: #{e.class}: #{e.message}")
        return nil
      end

      if retryable_status?(response.status) && attempt == 1
        Rails.logger.warn("[jev] status #{response.status}; retrying once")
        sleep(RETRY_BACKOFF)
        next
      end

      return response
    end
  end

  def retryable_status?(status)
    status == 429 || status >= 500
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{@api_key}"
      f.headers["Accept"] = "application/json"
      f.options.timeout = @timeout
      f.options.open_timeout = @timeout
      f.adapter Faraday.default_adapter
    end
  end

  def log_usage(body)
    Rails.logger.info("[jev] evaluate ok model=#{body['model']} input_tokens=#{body.dig('usage', 'input_tokens')}")
  end

  def log_failure(response)
    detail = response.body.is_a?(Hash) ? response.body["detail"] : response.body
    Rails.logger.warn("[jev] request failed status=#{response.status} detail=#{detail.inspect}")
  end
end
