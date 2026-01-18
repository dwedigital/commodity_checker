# frozen_string_literal: true

require "webmock/minitest"

# Helper module for API controller tests
module ApiTestHelper
  # Create an API key and return both the key object and raw key string
  def create_api_key(user:, tier: :starter, name: "Test Key")
    api_key = user.api_keys.create!(name: name, tier: tier)
    [ api_key, api_key.raw_key ]
  end

  # Set authorization header for requests
  def api_headers(raw_key)
    {
      "Authorization" => "Bearer #{raw_key}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  # Parse JSON response body
  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  # Make authenticated GET request
  def api_get(path, raw_key:, params: {})
    get path, params: params, headers: api_headers(raw_key)
  end

  # Make authenticated POST request
  def api_post(path, raw_key:, params: {})
    post path, params: params.to_json, headers: api_headers(raw_key)
  end

  # Make authenticated PATCH request
  def api_patch(path, raw_key:, params: {})
    patch path, params: params.to_json, headers: api_headers(raw_key)
  end

  # Make authenticated DELETE request
  def api_delete(path, raw_key:)
    delete path, headers: api_headers(raw_key)
  end

  # Stub tariff API search endpoint
  def stub_tariff_api_search(results)
    response_body = build_tariff_search_response(results)
    stub_request(:get, /trade-tariff.service.gov.uk.*search/)
      .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
  end

  # Stub tariff API commodity endpoint
  def stub_tariff_api_commodity(code, commodity)
    if commodity.nil?
      stub_request(:get, /trade-tariff.service.gov.uk.*commodities\/#{code}/)
        .to_return(status: 404, body: { error: "not found" }.to_json)
    else
      response_body = build_tariff_commodity_response(commodity)
      stub_request(:get, /trade-tariff.service.gov.uk.*commodities\/#{code}/)
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
    end
  end

  private

  def build_tariff_search_response(results)
    {
      data: {
        attributes: {
          type: "fuzzy_match",
          goods_nomenclature_match: {
            commodities: results.map do |r|
              {
                "_source" => {
                  "goods_nomenclature_item_id" => r[:code],
                  "description" => r[:description]
                },
                "_score" => r[:score] || 100
              }
            end,
            headings: []
          }
        }
      }
    }
  end

  def build_tariff_commodity_response(commodity)
    {
      data: {
        attributes: {
          goods_nomenclature_item_id: commodity[:code],
          formatted_description: commodity[:description],
          description: commodity[:description]
        }
      },
      included: commodity[:duty_rate] ? [
        {
          type: "measure",
          attributes: {
            duty_expression: {
              formatted_base: commodity[:duty_rate]
            }
          }
        }
      ] : []
    }
  end
end
