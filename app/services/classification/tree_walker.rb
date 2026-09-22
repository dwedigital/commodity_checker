module Classification
  # Walks the real tariff tree from a shortlist of candidate headings down to a
  # single declarable 10-digit commodity, asking the chooser at each fork.
  #
  # Heading step: choose among the candidate headings. If the chooser is not
  # confident (< 0.35) or there are no candidates, fall back to choosing a
  # chapter among all 98 and then a heading within it. Node steps: fetch the
  # heading's commodity tree and descend, presenting each node's children, until
  # the chosen node is declarable (or a depth cap is hit). Finally validate the
  # code against the tariff and enrich it.
  class TreeWalker
    LOW_CONFIDENCE = 0.35
    MAX_HEADING_OPTIONS = 40
    MAX_DEPTH = 12

    def initialize(tariff_tree: nil, tariff_service: nil)
      @tariff_tree = tariff_tree || TariffTree.new
      @tariff_service = tariff_service || TariffLookupService.new
    end

    def walk(analysis:, candidates:, chooser:)
      steps = []
      confidences = []
      product = product_context(analysis)

      heading, chapter_desc, heading_desc =
        select_heading(analysis, candidates, chooser, product, steps, confidences)
      return nil if heading.blank?

      base_path = [ chapter_desc, heading_desc ].compact.reject(&:blank?)
      code, node_path, node_confidences =
        walk_nodes(heading, product, base_path, chapter_of(heading), chooser, steps)
      return nil if code.blank?

      confidences.concat(node_confidences)
      enrich(
        code: code,
        path: base_path + node_path,
        steps: steps,
        confidences: confidences,
        analysis: analysis,
        chapter_desc: chapter_desc
      )
    end

    private

    attr_reader :tariff_tree, :tariff_service

    # Returns [heading_code, chapter_description, heading_description] or a nil
    # triple on failure.
    def select_heading(analysis, candidates, chooser, product, steps, confidences)
      if candidates.any?
        options = candidates.first(MAX_HEADING_OPTIONS).map { |c| { key: c[:code], label: c[:description] } }
        note = chapter_note_for(Array(analysis[:candidate_chapters]).first)
        result = chooser.choose(
          question: "Which 4-digit tariff heading best fits this product?",
          options: options,
          context: { product: product, path: [], level: :heading, chapter_note: note }
        )
        steps << step_record(:heading, options, result)

        if result && result[:confidence].to_f >= LOW_CONFIDENCE
          confidences << result[:confidence].to_f
          heading = result[:key]
          return [ heading, chapter_description(chapter_of(heading)), label_for(options, heading) ]
        end
      end

      choose_chapter_then_heading(chooser, product, steps, confidences)
    end

    def choose_chapter_then_heading(chooser, product, steps, confidences)
      chapter_options = tariff_tree.chapters.map { |c| { key: c[:code], label: c[:description] } }
      return [ nil, nil, nil ] if chapter_options.empty?

      chapter_result = chooser.choose(
        question: "Which 2-digit tariff chapter does this product belong to?",
        options: chapter_options,
        context: { product: product, path: [], level: :chapter, chapter_note: nil }
      )
      steps << step_record(:chapter, chapter_options, chapter_result)
      return [ nil, nil, nil ] unless chapter_result

      confidences << chapter_result[:confidence].to_f
      chapter = chapter_result[:key]
      chapter_desc = label_for(chapter_options, chapter)

      headings = tariff_tree.headings_for_chapter(chapter)
      return [ nil, nil, nil ] if headings.empty?

      heading_options = headings.first(MAX_HEADING_OPTIONS).map { |h| { key: h[:code], label: h[:description] } }
      heading_result = chooser.choose(
        question: "Which heading within chapter #{chapter} best fits this product?",
        options: heading_options,
        context: { product: product, path: [ chapter_desc ], level: :heading, chapter_note: tariff_tree.chapter_note(chapter) }
      )
      steps << step_record(:heading, heading_options, heading_result)
      return [ nil, nil, nil ] unless heading_result

      confidences << heading_result[:confidence].to_f
      [ heading_result[:key], chapter_desc, label_for(heading_options, heading_result[:key]) ]
    end

    # Returns [code, node_descriptions, node_confidences] or a nil triple.
    def walk_nodes(heading, product, base_path, chapter, chooser, steps)
      root = tariff_tree.tree_for_heading(heading)

      # Empty-heading leaf rule: nothing under the heading, so the heading itself
      # ("<heading>000000") is the leaf to validate.
      return [ root.item_id.presence || "#{heading}000000", [], [] ] if root.children.empty?

      node = root
      node_path = []
      confidences = []
      depth = 0
      first_node_step = true

      while node.children.any?
        depth += 1
        break if depth > MAX_DEPTH

        options = node.children.map { |child| { key: child.id, label: node_label(child) } }
        note = first_node_step ? tariff_tree.chapter_note(chapter) : nil
        result = chooser.choose(
          question: "Which sub-classification best fits this product?",
          options: options,
          context: { product: product, path: base_path + node_path, level: :node, chapter_note: note }
        )
        steps << step_record(:node, options, result)
        return [ nil, nil, nil ] unless result

        chosen = node.children.find { |child| child.id == result[:key] }
        return [ nil, nil, nil ] unless chosen

        confidences << result[:confidence].to_f
        node_path << chosen.description
        node = chosen
        first_node_step = false
        break if chosen.declarable
      end

      [ node.item_id, node_path, confidences ]
    end

    def enrich(code:, path:, steps:, confidences:, analysis:, chapter_desc:)
      digits = code.to_s.gsub(/\D/, "")
      commodity = tariff_service.get_commodity(digits)

      {
        commodity_code: digits,
        confidence: overall_confidence(confidences),
        reasoning: build_reasoning(analysis, path, digits),
        category: chapter_desc,
        validated: !commodity.nil?,
        official_description: commodity&.dig(:description),
        duty_rate: commodity&.dig(:duty_rate),
        path: path,
        steps: steps
      }
    end

    def overall_confidence(confidences)
      return 0.0 if confidences.empty?

      confidences.reduce(1.0) { |product, c| product * c }.round(4)
    end

    def build_reasoning(analysis, path, code)
      trail = path.reject(&:blank?).join(" › ")
      formatted = format_code(code)
      parts = []
      parts << analysis[:product_summary].to_s.strip if analysis[:product_summary].present?
      parts << (trail.present? ? "Classified as #{formatted} via #{trail}." : "Classified as #{formatted}.")
      parts.join(" ")
    end

    # The product context handed to the chooser: summary, salient attributes,
    # measurements, and the original description, capped near 3000 chars.
    def product_context(analysis)
      lines = []
      lines << analysis[:product_summary].to_s

      attrs = analysis[:attributes].is_a?(Hash) ? analysis[:attributes] : {}
      pairs = attrs.filter_map do |key, value|
        text = value.to_s.strip
        "#{key.to_s.humanize}: #{text}" if text.present? && text.downcase != "unknown"
      end
      lines << "Attributes: #{pairs.join(', ')}" if pairs.any?

      numeric = Array(analysis[:numeric_facts]).reject(&:blank?)
      lines << "Measurements: #{numeric.join('; ')}" if numeric.any?

      original = analysis[:original_description].to_s.strip
      lines << "Original description: #{original}" if original.present?

      lines.reject(&:blank?).join("\n")[0, 3000]
    end

    def step_record(level, options, result)
      {
        level: level,
        options_count: options.size,
        chosen_key: result && result[:key],
        confidence: result && result[:confidence],
        probabilities: result && result[:probabilities],
        reasoning: result && result[:reasoning]
      }
    end

    def node_label(node)
      return node.description if node.declarable

      "#{node.description} (category with sub-classifications)"
    end

    def chapter_note_for(chapter)
      return nil if chapter.blank?

      tariff_tree.chapter_note(chapter)
    end

    def chapter_description(chapter)
      chapters_map[chapter]&.dig(:description)
    end

    def chapters_map
      @chapters_map ||= tariff_tree.chapters.index_by { |c| c[:code] }
    end

    def chapter_of(heading)
      heading.to_s.gsub(/\D/, "")[0, 2]
    end

    def label_for(options, key)
      options.find { |o| o[:key] == key }&.dig(:label)
    end

    # "6109100010" -> "6109 10 0010", matching how codes read on the site.
    def format_code(code)
      digits = code.to_s.gsub(/\D/, "")
      return digits if digits.length < 6

      [ digits[0, 4], digits[4, 2], digits[6..].presence ].compact.join(" ")
    end
  end
end
