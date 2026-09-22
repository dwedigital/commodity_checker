module Classification
  # One Claude call that turns a raw, scraped product description into structured
  # classification facts: a plain summary, a handful of short customs-officer
  # search phrases, salient attributes, numeric facts, and the 1-3 most likely
  # chapters. Structured outputs (json_schema) guarantee the response parses.
  class ProductAnalyzer
    include AnthropicClient

    MODEL = :"claude-sonnet-5"
    MAX_TOKENS = 1200

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert UK customs classifier. You read a product description and
      extract the facts needed to classify it under the UK Trade Tariff, without
      guessing a code yourself.

      How UK/HS classification works, so your facts point at the right place:
      - GRI 1: goods are classified by the terms of the headings and the section
        and chapter notes. What the thing physically IS matters more than what it
        is marketed as.
      - GRI 3(b): for composite goods, sets, and mixtures, classification follows
        the material or component that gives the goods their essential character.
      - Parts vs complete articles are classified differently; note whether the
        item is a complete article or a part/accessory.
      - Pet toys are NOT chapter 95; they classify by their material (for example
        3926 plastic or 6307 textile).
      - Fancy dress costumes are apparel (chapters 61/62), not chapter 95, unless
        they are flimsy and not designed for repeated use.
      - Electric kettles are 8516 (heading 8516, subheading 79).
      - A tote or shopping bag with a textile outer surface is 4202 (subheading
        4202 92).

      Give material, construction (knitted / woven / moulded / cast / etc.),
      function or use, and any power source when they bear on classification.
      Keep search_phrases to how a customs officer would name the goods; never put
      words like tariff, HS, HTS, code, classification, or import in a phrase.
    PROMPT

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[product_summary search_phrases attributes numeric_facts candidate_chapters],
      properties: {
        product_summary: {
          type: "string",
          description: "One sentence: what the thing IS, not marketing copy."
        },
        search_phrases: {
          type: "array",
          description: "2 to 4 short noun phrases of 1-4 words, most specific first.",
          items: { type: "string" }
        },
        attributes: {
          type: "object",
          additionalProperties: false,
          required: %w[material construction function_or_use gender_or_age power_source is_set_or_kit],
          properties: {
            material: { type: "string" },
            construction: { type: "string", description: "e.g. knitted, woven, moulded, cast" },
            function_or_use: { type: "string" },
            gender_or_age: { type: "string" },
            power_source: { type: "string" },
            is_set_or_kit: { type: "string", enum: %w[yes no unknown] }
          }
        },
        numeric_facts: {
          type: "array",
          description: "Measurements with units as stated, e.g. '1.7 litre', '55 inch screen', '100% polyester'.",
          items: { type: "string" }
        },
        candidate_chapters: {
          type: "array",
          description: "1 to 3 two-digit chapter strings, most likely first.",
          items: { type: "string" }
        }
      }
    }.freeze

    def initialize(client: nil)
      @client = client
    end

    # Returns the analysis Hash (symbolized keys) or nil on failure.
    def analyze(description)
      return nil if description.blank?

      response = client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        thinking: { type: "adaptive" },
        output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
        system_: SYSTEM_PROMPT,
        messages: [ { role: "user", content: "Product description:\n#{description}" } ]
      )

      record_usage(response)
      # With adaptive thinking the text block is not necessarily the first block.
      text = response.content.find { |block| block.type == :text }&.text
      normalize(LlmResponseParser.extract_json(text))
    rescue Anthropic::Errors::Error => e
      Rails.logger.error("ProductAnalyzer Claude error: #{e.message}")
      nil
    rescue => e
      Rails.logger.error("ProductAnalyzer failed: #{e.message}")
      nil
    end

    private

    def client
      @client ||= anthropic_client
    end

    def record_usage(response)
      usage = response.usage
      return unless usage

      TokenMeter.record(input: usage.input_tokens, output: usage.output_tokens)
    end

    # Guard against a malformed response and coerce chapter strings to two digits.
    def normalize(analysis)
      return nil unless analysis.is_a?(Hash) && analysis[:product_summary].present?

      analysis[:search_phrases] = Array(analysis[:search_phrases]).map(&:to_s).reject(&:blank?)
      analysis[:numeric_facts] = Array(analysis[:numeric_facts]).map(&:to_s).reject(&:blank?)
      analysis[:candidate_chapters] = Array(analysis[:candidate_chapters])
        .map { |c| c.to_s.gsub(/\D/, "")[0, 2] }
        .reject(&:blank?)
        .uniq
      analysis[:attributes] = analysis[:attributes].is_a?(Hash) ? analysis[:attributes] : {}
      analysis
    end
  end
end
