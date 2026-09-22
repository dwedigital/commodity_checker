module Classification
  # Shared Anthropic client setup for the classification services. Mixed into
  # ProductAnalyzer and ClaudeChooser so they build the client and read the API
  # key the same way the rest of the app does (credentials first, then ENV).
  module AnthropicClient
    private

    def anthropic_client
      @anthropic_client ||= Anthropic::Client.new(api_key: anthropic_api_key)
    end

    def anthropic_api_key
      Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
    end
  end
end
