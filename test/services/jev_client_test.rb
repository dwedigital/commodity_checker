# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class JevClientTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.typesafe.ai/v1/systemone"

  SUCCESS_BODY = {
    "model" => "jev-1.13.0",
    "answers" => {
      "leaf" => {
        "type" => "choice",
        "choice" => "6109902000",
        "confidence" => 0.99,
        "probabilities" => { "6109902000" => 0.99, "6109909000" => 0.01 }
      }
    },
    "usage" => { "input_tokens" => 605, "output_tokens" => 126 }
  }.freeze

  def setup
    @client = JevClient.new(api_key: "test-key", timeout: 2)
  end

  def stub_success
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: SUCCESS_BODY.to_json
    )
  end

  def sample_questions
    { "leaf" => JevClient.choice(instructions: "Which line?", criteria: { "6109100010" => "Of cotton > T-shirts" }) }
  end

  # ---------------------------------------------------------------------------
  # configured?
  # ---------------------------------------------------------------------------

  test "configured? is true with a key and false without one" do
    assert JevClient.new(api_key: "abc").configured?
    refute JevClient.new(api_key: nil).configured?
    refute JevClient.new(api_key: "").configured?
  end

  test "evaluate returns nil and makes no request when not configured" do
    client = JevClient.new(api_key: nil)

    assert_nil client.evaluate(state: { product: "x" }, questions: sample_questions)
    assert_not_requested :post, ENDPOINT
  end

  # ---------------------------------------------------------------------------
  # request shape
  # ---------------------------------------------------------------------------

  test "evaluate posts model, state and a single choice question with criteria" do
    stub = stub_request(:post, ENDPOINT)
      .with(headers: { "Authorization" => "Bearer test-key" }) do |request|
        body = JSON.parse(request.body)
        body["model"] == "jev-latest" &&
          body["state"] == { "product" => "a knitted cotton t-shirt", "classified_so_far" => "Chapter 61" } &&
          body["questions"].keys == [ "leaf" ] &&
          body["questions"]["leaf"]["type"] == "choice" &&
          body["questions"]["leaf"]["instructions"] == "Which line?" &&
          body["questions"]["leaf"]["criteria"] == { "6109100010" => "Of cotton > T-shirts" }
      end
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: SUCCESS_BODY.to_json)

    @client.evaluate(
      state: { product: "a knitted cotton t-shirt", classified_so_far: "Chapter 61" },
      questions: sample_questions
    )

    assert_requested stub
  end

  # ---------------------------------------------------------------------------
  # response mapping
  # ---------------------------------------------------------------------------

  test "evaluate returns the parsed answers, usage and model on success" do
    stub_success

    result = @client.evaluate(state: { product: "x" }, questions: sample_questions)

    assert_equal "jev-1.13.0", result["model"]
    assert_equal "6109902000", result.dig("answers", "leaf", "choice")
    assert_in_delta 0.99, result.dig("answers", "leaf", "confidence"), 0.0001
    assert_equal 605, result.dig("usage", "input_tokens")
  end

  # ---------------------------------------------------------------------------
  # failure handling
  # ---------------------------------------------------------------------------

  test "evaluate returns nil on a 422 validation error without retrying" do
    stub = stub_request(:post, ENDPOINT).to_return(
      status: 422,
      headers: { "Content-Type" => "application/json" },
      body: { detail: [ { type: "missing", loc: %w[body questions], msg: "Field required" } ] }.to_json
    )

    assert_nil @client.evaluate(state: { product: "x" }, questions: {})
    assert_requested stub, times: 1
  end

  test "evaluate retries once then returns nil on repeated 500s" do
    stub = stub_request(:post, ENDPOINT).to_return(status: 500, body: "{}")

    @client.stub(:sleep, nil) do
      assert_nil @client.evaluate(state: { product: "x" }, questions: sample_questions)
    end

    assert_requested stub, times: 2
  end

  test "evaluate retries once then returns nil on a timeout" do
    # A real socket timeout surfaces as Faraday::TimeoutError; WebMock's
    # #to_timeout maps to ConnectionFailed in this adapter version, so raise the
    # real class to exercise the timeout branch deterministically.
    stub = stub_request(:post, ENDPOINT).to_raise(Faraday::TimeoutError)

    @client.stub(:sleep, nil) do
      assert_nil @client.evaluate(state: { product: "x" }, questions: sample_questions)
    end

    assert_requested stub, times: 2
  end

  test "evaluate retries a transient 500 and returns the second success" do
    stub_request(:post, ENDPOINT)
      .to_return(status: 500, body: "{}").then
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: SUCCESS_BODY.to_json)

    @client.stub(:sleep, nil) do
      result = @client.evaluate(state: { product: "x" }, questions: sample_questions)
      assert_equal "6109902000", result.dig("answers", "leaf", "choice")
    end
  end

  test "evaluate returns nil without retrying on a connection failure" do
    stub = stub_request(:post, ENDPOINT).to_raise(Faraday::ConnectionFailed.new("refused"))

    assert_nil @client.evaluate(state: { product: "x" }, questions: sample_questions)
    assert_requested stub, times: 1
  end

  # ---------------------------------------------------------------------------
  # question builders
  # ---------------------------------------------------------------------------

  test "choice builder returns a typed choice question with criteria" do
    question = JevClient.choice(instructions: "Pick one", criteria: { "a" => "A", "b" => "B" })

    assert_equal "choice", question[:type]
    assert_equal "Pick one", question[:instructions]
    assert_equal({ "a" => "A", "b" => "B" }, question[:criteria])
  end

  test "noul builder returns a typed noul question" do
    question = JevClient.noul(instructions: "Is it knitted?")

    assert_equal "noul", question[:type]
    assert_equal "Is it knitted?", question[:instructions]
  end

  test "score builder returns a typed score question with an array of levels" do
    question = JevClient.score(instructions: "Rate it", levels: [ "low", "medium", "high" ])

    assert_equal "score", question[:type]
    assert_equal [ "low", "medium", "high" ], question[:criteria]
  end
end
