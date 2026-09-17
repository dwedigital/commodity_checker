ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Load test support files
Dir[Rails.root.join("test", "support", "**", "*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include VCR and LLM mock helpers
    include VCRTestHelper
    include LlmMockHelper
  end
end

# Rails loads routes lazily under `rails test`, but Devise only sets
# OmniAuth.config.path_prefix while evaluating `devise_for`. The OmniAuth
# middleware runs ahead of the router, so on a process's very first request the
# prefix is still nil, the middleware declines the request, and it falls through
# to Devise's passthru action as a 404. Loading the routes up front removes that
# first-request-only failure.
Rails.application.reload_routes_unless_loaded

# Sign in with Google runs against OmniAuth's test mode: the request phase
# redirects straight to the callback with a canned auth hash, so tests never
# reach Google.
OmniAuth.config.test_mode = true
OmniAuth.config.logger = Logger.new(File::NULL)

class ActionDispatch::IntegrationTest
  include OmniauthTestHelper
  include OauthTestHelper

  setup do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end
