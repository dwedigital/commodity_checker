# Executes MCP tool calls against the same services the REST API and browser
# extension use.
#
# URL lookups run synchronously here, unlike POST /api/v1/commodity-codes/suggest-from-url
# which queues a batch job. An agent in a conversation wants the answer in the
# same turn, and ApiCommodityService#suggest_from_url is already synchronous;
# only the public endpoint wraps it in a job.
#
# Every return value is a Hash. A Hash carrying an :error key is a failed tool
# call, which the controller reports as isError rather than as a protocol error:
# a page that would not scrape is a result the model should see and work around,
# not a broken request.
module Mcp
  class ToolRunner
    MAX_SEARCH_RESULTS = 50
    MAX_RECENT_LOOKUPS = 100

    def initialize(user:, commodity_service: ApiCommodityService.new, tariff_service: TariffLookupService.new)
      @user = user
      @commodity_service = commodity_service
      @tariff_service = tariff_service
    end

    def call(name, arguments)
      args = (arguments || {}).with_indifferent_access

      case name
      when "lookup_from_url"          then lookup_from_url(args)
      when "lookup_from_description"  then lookup_from_description(args)
      when "search_codes"             then search_codes(args)
      when "get_code"                 then get_code(args)
      when "list_recent_lookups"      then list_recent_lookups(args)
      else
        error("unknown_tool", "No such tool: #{name}")
      end
    end

    private

    attr_reader :user, :commodity_service, :tariff_service

    def lookup_from_url(args)
      url = args[:url].to_s.strip
      return error("invalid_argument", "url is required") if url.blank?
      return error("invalid_argument", "url must be a valid http or https URL") unless valid_url?(url)

      return allowance_error if out_of_lookups?

      result = commodity_service.suggest_from_url(url)
      return error("lookup_failed", result[:error], url: url, scraped_product: result[:scraped_product]) if result[:error]

      suggestion(result, url: url, description: nil)
    end

    def lookup_from_description(args)
      description = args[:description].to_s.strip
      return error("invalid_argument", "description is required") if description.blank?

      return allowance_error if out_of_lookups?

      result = commodity_service.suggest_from_description(description)
      return error("lookup_failed", result[:error], description: description) if result[:error]

      suggestion(result, url: nil, description: description)
    end

    def search_codes(args)
      query = args[:query].to_s.strip
      return error("invalid_argument", "query is required") if query.blank?

      limit = clamp(args[:limit], default: 10, max: MAX_SEARCH_RESULTS)
      results = tariff_service.search(query).first(limit)

      {
        query: query,
        count: results.size,
        results: results.map do |result|
          {
            code: result[:code],
            formatted_code: format_code(result[:code]),
            description: result[:description],
            score: result[:score]
          }.compact
        end
      }
    end

    def get_code(args)
      code = args[:code].to_s.gsub(/\D/, "")
      return error("invalid_argument", "code must contain at least 6 digits") if code.length < 6

      commodity = tariff_service.get_commodity(code)
      return error("not_found", "Commodity code #{code} was not found in the UK Trade Tariff", code: code) if commodity.nil?

      {
        code: commodity[:code],
        formatted_code: format_code(commodity[:code]),
        description: commodity[:description],
        duty_rate: commodity[:duty_rate],
        notes: commodity[:notes]
      }.compact
    end

    def list_recent_lookups(args)
      limit = clamp(args[:limit], default: 20, max: MAX_RECENT_LOOKUPS)

      scope = user.product_lookups.order(created_at: :desc)

      if args[:since].present?
        since = parse_time(args[:since])
        return error("invalid_argument", "since must be an ISO 8601 date or timestamp") if since.nil?

        scope = scope.where(created_at: since..)
      end

      lookups = scope.limit(limit)

      {
        count: lookups.size,
        lookups: lookups.map { |lookup| lookup_summary(lookup) }
      }
    end

    # Shared shape for both lookup tools, so the model sees one result format.
    #
    # The lookup is always recorded. ProductLookup is what lookups_this_month
    # counts, so letting a caller opt out of saving would let it opt out of the
    # monthly allowance too.
    def suggestion(result, url:, description:)
      saved = save_lookup(result, url: url, description: description)

      {
        commodity_code: result[:commodity_code],
        formatted_code: format_code(result[:commodity_code]),
        confidence: result[:confidence],
        validated: result[:validated],
        official_description: result[:official_description],
        duty_rate: result[:duty_rate],
        category: result[:category],
        reasoning: result[:reasoning],
        scraped_product: result[:scraped_product],
        source_url: url,
        saved_to_account: saved.present?,
        product_lookup_id: saved&.id
      }.compact
    end

    def save_lookup(result, url:, description:)
      scraped = result[:scraped_product] || {}

      ProductLookup.create!(
        user: user,
        url: url,
        lookup_type: url.present? ? :url : :description,
        title: scraped[:title],
        description: description || scraped[:description],
        brand: scraped[:brand],
        category: scraped[:category] || result[:category],
        material: scraped[:material],
        image_url: scraped[:image_url],
        retailer_name: scraped[:retailer],
        suggested_commodity_code: result[:commodity_code],
        commodity_code_confidence: result[:confidence],
        llm_reasoning: result[:reasoning],
        scrape_status: url.present? ? :completed : nil,
        scraped_at: url.present? ? Time.current : nil
      )
    rescue ActiveRecord::RecordInvalid => e
      # A lookup that cannot be filed is still a lookup worth returning.
      Rails.logger.error("MCP: failed to save ProductLookup: #{e.message}")
      nil
    end

    def lookup_summary(lookup)
      {
        id: lookup.id,
        created_at: lookup.created_at.iso8601,
        lookup_type: lookup.lookup_type,
        url: lookup.url,
        title: lookup.title,
        retailer: lookup.retailer_name,
        commodity_code: lookup.display_commodity_code,
        formatted_code: format_code(lookup.display_commodity_code),
        confirmed: lookup.commodity_code_confirmed?,
        confidence: lookup.commodity_code_confidence&.to_f
      }.compact
    end

    # A lookup counts the same wherever it comes from — the website, the
    # extension, or an agent over MCP — so one monthly allowance covers them all.
    # Searching the tariff and reading saved lookups are not lookups and are not
    # metered.
    def out_of_lookups?
      !user.can_perform_lookup?
    end

    def allowance_error
      error("monthly_limit_reached",
            "This account has used its #{User::FREE_MONTHLY_LOOKUP_LIMIT} lookups for this month. " \
            "The allowance is shared across the website, the browser extension and MCP, and resets " \
            "at the start of next month.",
            lookups_this_month: user.lookups_this_month,
            lookups_remaining: 0)
    end

    def clamp(value, default:, max:)
      limit = value.presence&.to_i || default
      limit.clamp(1, max)
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    # "6109100010" -> "6109 10 0010", matching how codes read on the site.
    def format_code(code)
      digits = code.to_s.gsub(/\D/, "")
      return nil if digits.blank?
      return digits if digits.length < 6

      [ digits[0, 4], digits[4, 2], digits[6..].presence ].compact.join(" ")
    end

    def error(code, message, **context)
      { error: code, message: message.presence || "The lookup could not be completed" }.merge(context.compact)
    end
  end
end
