module Classification
  # A Chooser backed by TypeSafe AI's "Jev" decision model (see JevClient and
  # claude/implementations/jev-chooser.md). Each decision becomes a single
  # `choice` question whose criteria map the option keys to their labels; Jev
  # returns the chosen key with calibrated probabilities and no free text.
  #
  # Jev is documented as weak at numeric comparisons (weights, capacities,
  # powers, thresholds). On a level whose option labels read as numeric bands
  # (numeric_level?), this chooser delegates the whole decision to a `fallback`
  # chooser when one was supplied, tagging the result "claude(numeric)"; without
  # a fallback it still asks Jev but flags the caveat in `reasoning`.
  #
  # Constructed with no arguments by Classification::Choosers when
  # TARIFFIK_CHOOSER=jev; pass `fallback:` to enable the numeric hand-off.
  class JevChooser < Chooser
    QUESTION_KEY = "choice"
    MAX_OPTIONS = 255

    # Labels that read as a numeric-threshold branch, where Jev is unreliable.
    # ASCII "<"/">" only count next to a digit, so a " > " path separator in a
    # label (labels include path context) is not mistaken for a comparison.
    NUMERIC_LEVEL_PATTERNS = [
      /\d\s*%/,
      %r{\d\s*(?:mm|cm|dm|dam|hm|km|nm|kg|hg|dag|dg|cg|mg|kw|mw|kva|kv|ghz|mhz|khz|hz|ml|cl|dl|dal|hl|cc|kcal|bar|dpi|g/m|kg/m|g|w|v)\b}i,
      /\b(?:exceeding|not exceeding|more than|less than|of a weight|of a capacity|of a power)\b/i,
      /[≤≥]/,
      /\d\s*[<>]|[<>]\s*\d/
    ].freeze

    # True when any option label reads as a numeric-threshold branch.
    def self.numeric_level?(options)
      Array(options).any? do |opt|
        label = (opt[:label] || opt["label"]).to_s
        NUMERIC_LEVEL_PATTERNS.any? { |pattern| label.match?(pattern) }
      end
    end

    def initialize(client: nil, fallback: nil)
      @client = client
      @fallback = fallback
    end

    def choose(question:, options:, context:)
      options = Array(options)
      return nil if options.empty? || options.size > MAX_OPTIONS

      numeric = self.class.numeric_level?(options)

      if numeric && @fallback
        result = @fallback.choose(question: question, options: options, context: context)
        return nil unless result

        return result.merge(chooser: "claude(numeric)")
      end

      ask_jev(question: question, options: options, context: context, numeric: numeric)
    rescue => e
      Rails.logger.warn("[jev] chooser failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def ask_jev(question:, options:, context:, numeric:)
      state = {
        product: context[:product],
        classified_so_far: Array(context[:path]).join(" > ")
      }
      questions = {
        QUESTION_KEY => JevClient.choice(instructions: question, criteria: criteria_for(options))
      }

      response = client.evaluate(state: state, questions: questions)
      return nil unless response

      answer = response.dig("answers", QUESTION_KEY)
      return nil unless answer.is_a?(Hash) && answer["choice"].present?

      confidence = answer["confidence"]
      {
        key: answer["choice"],
        confidence: confidence,
        probabilities: answer["probabilities"] || {},
        reasoning: reasoning_for(confidence, numeric),
        chooser: "jev"
      }
    end

    # Jev wants criteria as key => a unique, non-empty label. Blank labels fall
    # back to the key; a label shared by two options is suffixed with the key so
    # every description stays distinct.
    def criteria_for(options)
      resolved = options.map { |opt| [ key_for(opt), label_for(opt) ] }
      counts = resolved.each_with_object(Hash.new(0)) { |(_key, label), acc| acc[label] += 1 }

      resolved.each_with_object({}) do |(key, label), criteria|
        criteria[key] = counts[label] > 1 ? "#{label} (#{key})" : label
      end
    end

    def key_for(opt)
      (opt[:key] || opt["key"]).to_s
    end

    def label_for(opt)
      label = (opt[:label] || opt["label"]).to_s.strip
      label.empty? ? key_for(opt) : label
    end

    def reasoning_for(confidence, numeric)
      base = "jev p=#{confidence}"
      numeric ? "#{base} (numeric level, no fallback; verify the threshold)" : base
    end

    def client
      @client ||= JevClient.new
    end
  end
end
