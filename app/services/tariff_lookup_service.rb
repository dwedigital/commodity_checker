class TariffLookupService
  BASE_URL = "https://www.trade-tariff.service.gov.uk/api/v2".freeze

  def initialize
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  # Search for commodity codes by keyword
  def search(query)
    response = @conn.get("search", q: query)

    return [] unless response.success?

    parse_search_results(response.body)
  rescue Faraday::Error => e
    Rails.logger.error("Tariff API search failed: #{e.message}")
    []
  end

  # Get details for a specific commodity code
  def get_commodity(code)
    # Remove any spaces or dashes from code
    code = code.gsub(/[\s-]/, "")

    response = @conn.get("commodities/#{code}")

    return nil unless response.success?

    parse_commodity(response.body)
  rescue Faraday::Error => e
    Rails.logger.error("Tariff API commodity lookup failed: #{e.message}")
    nil
  end

  # Get headings (4-digit codes) for a chapter
  def get_headings(chapter_code)
    response = @conn.get("chapters/#{chapter_code}")

    return [] unless response.success?

    parse_headings(response.body)
  rescue Faraday::Error => e
    Rails.logger.error("Tariff API headings lookup failed: #{e.message}")
    []
  end

  private

  def parse_search_results(body)
    results = []
    data = body["data"]
    return results unless data

    search_type = data.dig("attributes", "type")

    case search_type
    when "fuzzy_match"
      # Fuzzy search returns commodities nested in goods_nomenclature_match
      commodities = data.dig("attributes", "goods_nomenclature_match", "commodities") || []
      headings = data.dig("attributes", "goods_nomenclature_match", "headings") || []

      # Process commodities first (more specific)
      commodities.first(15).each do |item|
        source = item["_source"] || {}
        results << {
          code: source["goods_nomenclature_item_id"],
          description: source["description"],
          score: item["_score"]
        }
      end

      # Then headings if we need more results
      headings.first(5).each do |item|
        source = item["_source"] || {}
        results << {
          code: source["goods_nomenclature_item_id"],
          description: source["description"],
          score: item["_score"]
        }
      end

    when "exact_match"
      # Exact match points to a specific heading or commodity
      entry = data.dig("attributes", "entry") || {}
      endpoint = entry["endpoint"]
      id = entry["id"]

      if endpoint && id
        # Fetch the actual heading/commodity details
        details = fetch_entry_details(endpoint, id)
        results.concat(details) if details
      end
    end

    results.compact.reject { |r| r[:code].nil? }
  end

  def fetch_entry_details(endpoint, id)
    results = []

    case endpoint
    when "headings"
      response = @conn.get("headings/#{id}")
      return [] unless response.success?

      # Get commodities under this heading from included data
      included = response.body["included"] || []
      included.select { |i| i["type"] == "commodity" }.first(20).each do |item|
        attrs = item["attributes"] || {}
        results << {
          code: attrs["goods_nomenclature_item_id"],
          description: attrs["formatted_description"] || attrs["description"],
          score: 100 # Exact match
        }
      end

    when "commodities"
      response = @conn.get("commodities/#{id}")
      return [] unless response.success?

      attrs = response.body.dig("data", "attributes") || {}
      results << {
        code: attrs["goods_nomenclature_item_id"],
        description: attrs["formatted_description"] || attrs["description"],
        score: 100
      }
    end

    results
  rescue Faraday::Error => e
    Rails.logger.error("Tariff API fetch entry failed: #{e.message}")
    []
  end

  def parse_commodity(body)
    data = body["data"]
    return nil unless data

    attrs = data["attributes"] || {}

    {
      code: attrs["goods_nomenclature_item_id"],
      description: attrs["formatted_description"] || attrs["description"],
      duty_rate: extract_duty_rate(body),
      notes: attrs["chapter_note"]
    }
  end

  def parse_headings(body)
    headings = body.dig("included") || []

    headings.select { |h| h["type"] == "heading" }.map do |heading|
      attrs = heading["attributes"] || {}
      {
        code: attrs["goods_nomenclature_item_id"],
        description: attrs["formatted_description"] || attrs["description"]
      }
    end
  end

  def extract_duty_rate(body)
    # Try to find duty rate from included measures
    included = body["included"] || []
    measure = included.find { |i| i["type"] == "measure" && i.dig("attributes", "duty_expression") }

    measure&.dig("attributes", "duty_expression", "formatted_base")
  end
end
