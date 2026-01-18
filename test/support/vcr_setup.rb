# frozen_string_literal: true

require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/cassettes"
  config.hook_into :webmock

  # Filter sensitive data from recordings
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<TAVILY_API_KEY>") { ENV["TAVILY_API_KEY"] }
  config.filter_sensitive_data("<SCRAPINGBEE_API_KEY>") { ENV["SCRAPINGBEE_API_KEY"] }
  config.filter_sensitive_data("<RESEND_API_KEY>") { ENV["RESEND_API_KEY"] }

  # Don't record Claude API calls - use fixtures/mocks instead for LLM responses
  # LLM outputs are non-deterministic, so recorded cassettes would be misleading
  config.ignore_hosts "api.anthropic.com"

  # Allow localhost for test server
  config.ignore_localhost = true

  # Record mode options:
  # :once - Record once, replay forever (default, recommended for CI)
  # :new_episodes - Record new requests, replay existing
  # :none - Only replay, error on new requests (for CI)
  # :all - Always record (useful for updating cassettes)
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [ :method, :uri, :body ]
  }

  # Allow real HTTP connections when no cassette is loaded
  # (useful during development, but should be :none in CI)
  config.allow_http_connections_when_no_cassette = true
end

# Helper module for VCR in tests
module VCRTestHelper
  def with_cassette(name, options = {}, &block)
    VCR.use_cassette(name, options, &block)
  end
end
