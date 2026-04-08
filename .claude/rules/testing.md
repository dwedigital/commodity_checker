---
paths:
  - "test/**"
---

# Testing

## CRITICAL: Test Integrity Policy

**NEVER modify tests just to make them pass.** Tests define expected behavior. If a test fails:

1. **Assume the test is correct** - Tests verify specific, intended behavior
2. **Fix the code, not the test** - Implementation should match expected behavior
3. **Only modify a test if:** requirements have genuinely changed (confirmed by user), the test itself has a bug (rare), or you're adding new test cases

## Test Strategy

| API Type | Testing Method | Rationale |
|----------|---------------|-----------|
| UK Trade Tariff API | VCR cassettes | Deterministic, stable responses |
| Tavily Search API | VCR cassettes | Real search results, complex JSON |
| Web scraping | VCR cassettes | Captures real HTML for parsing |
| Anthropic Claude API | Mocks/stubs | LLM outputs are non-deterministic |

## Running Tests

```bash
bin/rails test                                          # All tests
bin/rails test test/services/                           # Service tests only
bin/rails test test/services/email_parser_service_test.rb      # Specific file
bin/rails test test/services/email_parser_service_test.rb:42   # Specific test
```

## Test Structure

```
test/
├── services/           # Service unit tests
├── cassettes/          # VCR recorded API responses (tariff_api/, tavily/, scraping/)
├── fixtures/
│   ├── llm_responses/  # JSON fixtures for Claude responses
│   └── *.yml           # Rails model fixtures
└── support/
    ├── vcr_setup.rb         # VCR configuration
    └── llm_mock_helper.rb   # Helpers for mocking Claude API
```

## Writing Tests

**For VCR tests (external APIs):**
```ruby
test "searches tariff API" do
  with_cassette("tariff_api/search_tshirt") do
    results = @service.search("cotton t-shirt")
    assert results.is_a?(Array)
    assert results.first.key?(:code)
  end
end
```

**For Claude API (use mocks):**
```ruby
test "suggests commodity code" do
  stub_commodity_suggestion(code: "6109100010", confidence: 0.85, reasoning: "Cotton t-shirt")
  result = @suggester.suggest("Cotton t-shirt")
  assert_equal "6109100010", result[:commodity_code]
end
```

## Adding Tests for New Services

1. Create test file in `test/services/`
2. Use `with_cassette` for external HTTP calls
3. Use `stub_*` helpers for Claude API
4. Test error handling (API failures, invalid responses)
5. Test edge cases (empty input, malformed data)

See `test/CLAUDE.md` for detailed testing guidelines.

## Testing Without External Services

1. **Without Resend**: Use `/dashboard/test_emails/new` to paste email content
2. **Without Claude API**: Remove API key, suggestions will return nil
3. **Without Tariff API**: Service returns empty array on failure
