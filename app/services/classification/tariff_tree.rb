require "cgi"

module Classification
  # Read-only client over the UK Trade Tariff API v2 (no auth). Exposes the
  # nomenclature as walkable structure: the 98 chapters, the headings under a
  # chapter, the nested commodity tree under a heading, and chapter notes.
  #
  # Every GET is cached for 24 hours (dev = memory_store, prod = solid_cache,
  # test = null_store). Failures are never cached and never raised: methods
  # return an empty collection or nil and log instead, so a flaky tariff API
  # degrades a lookup rather than crashing it.
  class TariffTree
    BASE_URL = "https://www.trade-tariff.service.gov.uk/api/v2".freeze
    TIMEOUT = 10
    CACHE_NAMESPACE = "tariff_tree:v1".freeze

    # One node of the commodity tree. Identity is item_id + producline_suffix,
    # because the same goods_nomenclature_item_id appears twice under some
    # headings (a suffix "10" grouping line and a suffix "80" declarable line).
    Node = Struct.new(
      :id, :item_id, :suffix, :indent, :declarable, :grouping, :description, :children,
      keyword_init: true
    )

    def initialize(cache: Rails.cache)
      @cache = cache
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    # All 98 chapters: [{ code: "61", item_id: "6100000000", description: "..." }]
    def chapters
      body = fetch_json("chapters")
      return [] unless body

      Array(body["data"]).filter_map do |c|
        attrs = c["attributes"] || {}
        item_id = attrs["goods_nomenclature_item_id"].to_s
        next if item_id.blank?

        { code: item_id[0, 2], item_id: item_id, description: clean(attrs["formatted_description"]) }
      end
    end

    # Headings under a chapter: [{ code: "6109", item_id: "6109000000", description: "..." }]
    def headings_for_chapter(two_digit)
      chapter = normalize(two_digit, 2)
      return [] if chapter.blank?

      body = fetch_json("chapters/#{chapter}")
      return [] unless body

      Array(body["included"]).select { |i| i["type"] == "heading" }.filter_map do |h|
        attrs = h["attributes"] || {}
        item_id = attrs["goods_nomenclature_item_id"].to_s
        next if item_id.blank?

        { code: item_id[0, 4], item_id: item_id, description: clean(attrs["formatted_description"] || attrs["description"]) }
      end
    end

    # Nested commodity tree for a heading. Returns a root Node (the heading
    # itself) whose children are built from the flat, ordered commodity list
    # using number_indents: a node's parent is the nearest preceding node with a
    # smaller indent. When a heading has no commodity children the root stands in
    # as the leaf, with item_id "<heading>000000" for the walker to validate.
    def tree_for_heading(four_digit)
      heading = normalize(four_digit, 4)
      body = fetch_json("headings/#{heading}")

      root_item = body&.dig("data", "attributes", "goods_nomenclature_item_id").to_s
      root_item = "#{heading}000000" if root_item.blank?
      root = Node.new(
        id: "#{root_item}/root",
        item_id: root_item,
        suffix: nil,
        indent: -1,
        declarable: body&.dig("data", "attributes", "declarable") ? true : false,
        grouping: true,
        description: clean(body&.dig("data", "attributes", "formatted_description")),
        children: []
      )
      return root unless body

      commodities = Array(body["included"]).select { |i| i["type"] == "commodity" }
      attach(commodities.map { |c| node_from(c) }, root)
      root
    end

    # The chapter note (markdown, up to ~10 KB) or nil.
    def chapter_note(two_digit)
      chapter = normalize(two_digit, 2)
      return nil if chapter.blank?

      body = fetch_json("chapters/#{chapter}")
      body&.dig("data", "attributes", "chapter_note").presence
    end

    private

    attr_reader :cache, :conn

    # Builds the parent/child links in place from the flat ordered node list.
    def attach(nodes, root)
      stack = [ root ]
      nodes.each do |node|
        stack.pop while stack.size > 1 && stack.last.indent >= node.indent
        stack.last.children << node
        stack.push(node)
      end
      root
    end

    def node_from(commodity)
      attrs = commodity["attributes"] || {}
      item_id = attrs["goods_nomenclature_item_id"].to_s
      suffix = attrs["producline_suffix"].to_s

      Node.new(
        id: "#{item_id}/#{suffix}",
        item_id: item_id,
        suffix: suffix,
        indent: attrs["number_indents"].to_i,
        declarable: attrs["declarable"] ? true : false,
        grouping: suffix != "80",
        description: clean(attrs["formatted_description"] || attrs["description"]),
        children: []
      )
    end

    # Cached GET. nil (failure/404) is never written, so a transient error does
    # not poison the cache for 24 hours; nil from cache.read therefore always
    # means a miss.
    def fetch_json(path)
      key = "#{CACHE_NAMESPACE}:#{path}"
      cached = cache.read(key)
      return cached unless cached.nil?

      body = http_get(path)
      cache.write(key, body, expires_in: 24.hours) unless body.nil?
      body
    end

    # One GET with a single retry on a timeout, connection error, or 5xx.
    def http_get(path)
      attempt = 0
      loop do
        attempt += 1
        begin
          response = conn.get(path)
          return response.body if response.success?
          next if response.status.to_i >= 500 && attempt < 2

          return nil
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          next if attempt < 2

          Rails.logger.warn("TariffTree GET #{path} failed: #{e.class} #{e.message}")
          return nil
        end
      end
    rescue Faraday::Error => e
      Rails.logger.warn("TariffTree GET #{path} error: #{e.class} #{e.message}")
      nil
    end

    def normalize(value, length)
      value.to_s.gsub(/\D/, "")[0, length]
    end

    # Strip HTML tags and unescape entities from a formatted_description.
    def clean(text)
      return "" if text.nil?

      CGI.unescapeHTML(text.to_s.gsub(/<[^>]+>/, " ")).squeeze(" ").strip
    end
  end
end
