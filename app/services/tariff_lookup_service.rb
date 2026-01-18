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
  # Falls back to searching individual terms if compound query returns no results
  def search(query)
    results = search_single(query)

    # If no results and query has multiple words, try fallback search
    if results.empty? && query.to_s.split.size > 1
      results = search_with_fallback(query)
    end

    results
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

  # Perform a single search query against the API
  def search_single(query)
    response = @conn.get("search", q: query)
    return [] unless response.success?

    parse_search_results(response.body)
  end

  # Fallback search: try individual terms and combine results
  def search_with_fallback(query)
    words = query.to_s.downcase.split
    stop_words = %w[a an the of for with in on and or]
    meaningful_words = words.reject { |w| stop_words.include?(w) || w.length < 3 }

    return [] if meaningful_words.empty?

    all_results = []

    # Search each meaningful term
    meaningful_words.each do |term|
      term_results = search_single(term)
      all_results.concat(term_results)
    end

    # Deduplicate by code, keeping highest score
    deduplicated = all_results.group_by { |r| r[:code] }.map do |_code, results|
      results.max_by { |r| r[:score] || 0 }
    end

    # Sort by score descending and limit results
    deduplicated.sort_by { |r| -(r[:score] || 0) }.first(20)
  end

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

      # Try to get commodities under this heading from included data
      included = response.body["included"] || []
      commodities = included.select { |i| i["type"] == "commodity" }

      if commodities.any?
        commodities.first(20).each do |item|
          attrs = item["attributes"] || {}
          results << {
            code: attrs["goods_nomenclature_item_id"],
            description: attrs["formatted_description"] || attrs["description"],
            score: 100 # Exact match
          }
        end
      else
        # API no longer includes commodities in response - return the heading itself
        heading_attrs = response.body.dig("data", "attributes") || {}
        results << {
          code: heading_attrs["goods_nomenclature_item_id"],
          description: heading_attrs["formatted_description"] || heading_attrs["description"],
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

    when "subheadings"
      response = @conn.get("subheadings/#{id}")
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
