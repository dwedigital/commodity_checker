# Testing - AI Assistant Context

This document provides comprehensive guidance for AI assistants working with the test suite.

## CRITICAL: Test Integrity Rules

### NEVER Modify Tests to Make Them Pass

**This is the most important rule.** Tests define the expected behavior of the system. When a test fails:

```
❌ WRONG: "The test expects X but the code does Y, so I'll change the test to expect Y"
✅ RIGHT: "The test expects X but the code does Y, so I'll fix the code to do X"
```

### When a Test Fails, Follow This Process

1. **Read the test carefully** - Understand what behavior it's verifying
2. **Assume the test is correct** - It was written to capture intended behavior
3. **Find the bug in the code** - The implementation doesn't match the specification
4. **Fix the implementation** - Make the code behave as the test expects
5. **Only then**, if you're 100% certain the test itself is wrong, consult the user

### The Only Valid Reasons to Modify a Test

1. **Requirements have changed** - The user has explicitly confirmed new behavior is desired
2. **The test has an actual bug** - Extremely rare; investigate thoroughly before concluding this
3. **Adding new test cases** - Extending coverage, not changing existing assertions
4. **Test data needs updating** - e.g., fixtures reference data that no longer exists

### Why This Matters

- Tests are the **specification** of correct behavior
- Modifying tests to match broken code **hides bugs**
- Future developers (and AI) will trust the tests to be correct
- A passing test suite with modified tests gives **false confidence**

## Test Architecture

### Directory Structure

```
test/
├── services/                    # Unit tests for service objects
│   ├── tariff_lookup_service_test.rb    (7 tests)
│   ├── email_parser_service_test.rb     (35 tests)
│   ├── order_matcher_service_test.rb    (18 tests)
│   └── llm_commodity_suggester_test.rb  (16 tests)
├── models/                      # Model unit tests
├── controllers/                 # Controller tests
├── integration/                 # Integration tests
├── system/                      # System/browser tests
├── cassettes/                   # VCR recorded HTTP responses
│   ├── tariff_api/              # UK Trade Tariff API responses
│   ├── tavily/                  # Tavily search API responses
│   └── scraping/                # Scraped web pages
├── fixtures/
│   ├── llm_responses/           # JSON fixtures for Claude API mocking
│   │   ├── commodity_suggestion_tshirt.json
│   │   └── email_classification_order.json
│   ├── users.yml                # User fixtures
│   ├── orders.yml               # Order fixtures
│   └── ...
└── support/
    ├── vcr_setup.rb             # VCR configuration
    └── llm_mock_helper.rb       # Claude API mocking helpers
```

### Testing Strategy by Component

| Component | Method | Why |
|-----------|--------|-----|
| TariffLookupService | VCR cassettes | Deterministic API, stable responses |
| EmailParserService | Unit tests (no HTTP) | Pure parsing logic, no external calls |
| OrderMatcherService | Database tests | Tests ActiveRecord queries |
| LlmCommoditySuggester | VCR + mocks | VCR for Tariff API, mocks for Claude |
| EmailClassifierService | Mocks | LLM responses are non-deterministic |
| ProductInfoFinderService | VCR + mocks | VCR for Tavily, mocks for Claude |

## VCR Usage

### Configuration

VCR is configured in `test/support/vcr_setup.rb`:

```ruby
VCR.configure do |config|
  config.cassette_library_dir = "test/cassettes"
  config.hook_into :webmock

  # Sensitive data is filtered
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<TAVILY_API_KEY>") { ENV["TAVILY_API_KEY"] }

  # Claude API is NOT recorded - use mocks instead
  config.ignore_hosts "api.anthropic.com"
end
```

### Using VCR in Tests

```ruby
test "searches for commodity codes" do
  with_cassette("tariff_api/search_cotton_tshirt") do
    results = @service.search("cotton t-shirt")

    # Assert on STRUCTURE, not specific values
    assert results.is_a?(Array)
    assert results.any?
    assert results.first.key?(:code)
    assert results.first.key?(:description)
  end
end
```

### VCR Best Practices

1. **Name cassettes descriptively**: `tariff_api/search_cotton_tshirt`, not `test1`
2. **Assert structure, not content**: Cassette data may change when re-recorded
3. **Don't assert on dates/times**: They become stale
4. **One cassette per scenario**: Don't reuse cassettes across unrelated tests

### Recording New Cassettes

Cassettes are recorded automatically on first run. To re-record:

```ruby
# Temporarily change record mode
with_cassette("tariff_api/new_test", record: :all) do
  # ...
end
```

Or delete the cassette file and run the test again.

## Mocking Claude API

Claude responses are non-deterministic, so we mock them instead of recording.

### Available Helpers (from `llm_mock_helper.rb`)

```ruby
# Stub a commodity suggestion response
stub_commodity_suggestion(
  code: "6109100010",
  confidence: 0.85,
  reasoning: "Cotton t-shirt falls under HS 6109"
)

# Stub an email classification response
stub_email_classification(
  type: "order_confirmation",
  confidence: 0.95,
  products: [{ name: "Widget", brand: "Acme" }]
)

# Stub raw Claude response (for edge cases)
stub_claude_response('{"commodity_code": "1234567890", ...}')

# Load a fixture file
fixture = load_llm_fixture("commodity_suggestion_tshirt")
```

### Example Test with Mocks

```ruby
test "suggests commodity code for product" do
  # Stub both APIs
  stub_tariff_search([
    { code: "6109100010", description: "T-shirts, cotton", score: 95 }
  ])
  stub_commodity_suggestion(
    code: "6109100010",
    confidence: 0.9,
    reasoning: "Cotton t-shirt"
  )
  stub_tariff_commodity("6109100010", {
    code: "6109100010",
    description: "T-shirts",
    duty_rate: "12%"
  })

  result = @suggester.suggest("Cotton t-shirt, blue")

  assert_equal "6109100010", result[:commodity_code]
  assert_equal true, result[:validated]
end
```

## Testing Patterns

### Testing Services Without External Dependencies

For services like `EmailParserService` that don't make HTTP calls:

```ruby
def build_email(subject: "Test", from_address: "test@example.com", body_text: "", body_html: nil)
  OpenStruct.new(
    subject: subject,
    from_address: from_address,
    body_text: body_text,
    body_html: body_html
  )
end

test "extracts tracking URL from email" do
  email = build_email(
    body_text: "Track here: https://www.royalmail.com/track?id=123"
  )
  parser = EmailParserService.new(email)

  urls = parser.extract_tracking_urls

  assert urls.any? { |u| u[:carrier] == "royal_mail" }
end
```

### Testing Database Queries

For services like `OrderMatcherService` that query the database:

```ruby
def setup
  @user = users(:one)  # Use fixtures
end

test "matches order by reference" do
  order = Order.create!(
    user: @user,
    order_reference: "ORD-123",
    retailer_name: "Test"
  )

  parsed_data = { order_reference: "ORD-123", tracking_urls: [], retailer_name: nil }
  matcher = OrderMatcherService.new(@user, parsed_data)

  assert_equal order, matcher.find_matching_order
end
```

### Testing Error Handling

Always test how services handle failures:

```ruby
test "returns nil when API fails" do
  stub_request(:get, /trade-tariff.service.gov.uk/)
    .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

  result = @service.search("test")

  assert_equal [], result  # Graceful degradation
end

test "returns nil for invalid JSON response" do
  stub_claude_response("not valid json")

  result = @suggester.suggest("product")

  assert_nil result
end
```

## Fixtures

### Model Fixtures

Located in `test/fixtures/*.yml`. Key fixtures:

**users.yml:**
```yaml
one:
  email: "user_one@example.com"
  encrypted_password: "$2a$12$..."
  inbound_email_token: "token_one"

two:
  email: "user_two@example.com"
  encrypted_password: "$2a$12$..."
  inbound_email_token: "token_two"
```

**orders.yml:**
```yaml
one:
  user: one
  source_email: one
  order_reference: ORD-001
  retailer_name: Test Retailer
  status: 1
```

### LLM Response Fixtures

Located in `test/fixtures/llm_responses/*.json`:

**commodity_suggestion_tshirt.json:**
```json
{
  "commodity_code": "6109100010",
  "confidence": 0.85,
  "reasoning": "Cotton t-shirt falls under HS code 6109",
  "category": "Apparel - T-shirts"
}
```

## Running Tests

```bash
# All tests
bin/rails test

# Service tests only
bin/rails test test/services/

# Specific file
bin/rails test test/services/email_parser_service_test.rb

# Specific test by line
bin/rails test test/services/email_parser_service_test.rb:42

# With verbose output
bin/rails test --verbose

# Stop on first failure
bin/rails test --fail-fast
```

## Adding Tests for New Services

1. Create `test/services/<service_name>_test.rb`
2. Follow the existing patterns:
   - `def setup` for initialization
   - Group tests by functionality with comments
   - Use descriptive test names
3. Determine testing strategy:
   - Pure logic → unit tests with mock objects
   - External HTTP → VCR cassettes
   - LLM calls → mock helpers
   - Database queries → use fixtures + create records
4. Cover:
   - Happy path
   - Edge cases (empty input, nil, malformed data)
   - Error handling (API failures, invalid responses)
   - User isolation (if applicable)

## Common Gotchas

1. **Parallel tests + database**: Tests run in parallel by default. Use transactions or be careful with shared state.

2. **VCR + webmock**: VCR uses webmock. If you stub a request manually, VCR won't record it.

3. **Fixture loading**: All fixtures are loaded by default (`fixtures :all`). This can cause constraint violations if fixtures are incomplete.

4. **Time-dependent tests**: Use `travel_to` for time-sensitive tests:
   ```ruby
   travel_to Time.zone.local(2026, 1, 15) do
     # Test code that depends on current time
   end
   ```

5. **OpenStruct in tests**: Requires `require "ostruct"` in Ruby 3.5+.
