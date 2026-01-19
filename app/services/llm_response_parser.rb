# Extracts JSON from Claude LLM responses
# Handles markdown code blocks and various response formats
class LlmResponseParser
  # Extract and parse JSON from an LLM response
  # @param content [String] The raw text content from the LLM response
  # @param symbolize_keys [Boolean] Whether to symbolize the hash keys (default: true)
  # @return [Hash, nil] The parsed JSON as a hash, or nil if parsing fails
  def self.extract_json(content, symbolize_keys: true)
    return nil if content.blank?

    # Extract JSON from response (handles markdown code blocks)
    json_match = content.match(/\{[\s\S]*\}/m)
    return nil unless json_match

    parsed = JSON.parse(json_match[0])
    symbolize_keys ? parsed.deep_symbolize_keys : parsed
  rescue JSON::ParserError => e
    Rails.logger.error("LlmResponseParser: Failed to parse JSON - #{e.message}")
    nil
  end

  # Extract JSON from Anthropic API response object
  # @param response [Anthropic::Response] The response from the Anthropic API
  # @param symbolize_keys [Boolean] Whether to symbolize the hash keys (default: true)
  # @return [Hash, nil] The parsed JSON as a hash, or nil if parsing fails
  def self.extract_json_from_response(response, symbolize_keys: true)
    content = response.content.first&.text
    extract_json(content, symbolize_keys: symbolize_keys)
  end
end
