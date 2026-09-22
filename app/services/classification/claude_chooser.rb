module Classification
  # A Chooser backed by one Claude call per decision. The option keys are baked
  # into the JSON schema's enum, so the model cannot return a key that is not on
  # offer. Deeper (:node) decisions use low effort; the coarser :chapter and
  # :heading decisions use medium effort.
  class ClaudeChooser < Chooser
    include AnthropicClient

    MODEL = :"claude-sonnet-5"
    MAX_TOKENS = 800
    PRODUCT_LIMIT = 3000
    CHAPTER_NOTE_LIMIT = 4000

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert UK customs classifier walking the UK Trade Tariff one
      decision at a time. You are shown a product and a fixed set of options at a
      single level of the nomenclature (chapter, heading, or a sub-line within a
      heading). Choose the single option whose terms best fit the goods.

      Classify by what the goods physically are, following GRI 1 (the terms of
      the headings and the section and chapter notes) and, for composite goods or
      sets, GRI 3(b) (essential character). Prefer a specific line over a residual
      "Other" line when the goods clearly fit it. Return only a key from the
      options and your confidence that it is correct.
    PROMPT

    def initialize(client: nil)
      @client = client
    end

    def choose(question:, options:, context:)
      keys = options.map { |o| o[:key].to_s }
      return nil if keys.empty?

      effort = context[:level] == :node ? "low" : "medium"

      response = client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        thinking: { type: "adaptive" },
        output_config: { effort: effort, format: { type: "json_schema", schema: schema_for(keys) } },
        system_: SYSTEM_PROMPT,
        messages: [ { role: "user", content: build_prompt(question, options, context) } ]
      )

      record_usage(response)
      build_result(response, keys)
    rescue Anthropic::Errors::Error => e
      Rails.logger.error("ClaudeChooser Claude error: #{e.message}")
      nil
    rescue => e
      Rails.logger.error("ClaudeChooser failed: #{e.message}")
      nil
    end

    private

    def client
      @client ||= anthropic_client
    end

    # The option keys go in the enum so an invalid key is impossible.
    def schema_for(keys)
      {
        type: "object",
        additionalProperties: false,
        required: %w[key confidence reasoning],
        properties: {
          key: { type: "string", enum: keys },
          confidence: { type: "number" },
          reasoning: { type: "string" }
        }
      }
    end

    def build_prompt(question, options, context)
      parts = []
      parts << "Product:\n#{context[:product].to_s[0, PRODUCT_LIMIT]}"

      path = Array(context[:path]).reject(&:blank?)
      parts << "Classification so far: #{path.join(' > ')}" if path.any?

      note = context[:chapter_note].to_s
      parts << "Relevant chapter note:\n#{note[0, CHAPTER_NOTE_LIMIT]}" if note.present?

      parts << question
      parts << "Options:"
      options.each { |o| parts << "- [#{o[:key]}] #{o[:label]}" }
      parts << "Reply with the key of the single best option."
      parts.join("\n\n")
    end

    def build_result(response, keys)
      # With adaptive thinking the text block is not necessarily the first block.
      text = response.content.find { |block| block.type == :text }&.text
      parsed = LlmResponseParser.extract_json(text)
      return nil unless parsed.is_a?(Hash)

      key = parsed[:key].to_s
      return nil unless keys.include?(key)

      confidence = parsed[:confidence].to_f.clamp(0.0, 1.0)
      probabilities = keys.index_with { |k| k == key ? confidence : 0.0 }

      {
        key: key,
        confidence: confidence,
        probabilities: probabilities,
        reasoning: parsed[:reasoning],
        chooser: "claude"
      }
    end

    def record_usage(response)
      usage = response.usage
      return unless usage

      TokenMeter.record(input: usage.input_tokens, output: usage.output_tokens)
    end
  end
end
