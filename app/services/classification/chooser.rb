module Classification
  # Interface for the decision maker the TreeWalker asks at each step. A chooser
  # is handed a question, a fixed set of options, and context, and returns which
  # option it picked with a confidence and per-option probabilities.
  #
  # This contract is shared with alternative implementations (ClaudeChooser and a
  # separately built JevChooser), so it must not drift.
  #
  #   question: String
  #   options:  Array of { key: String, label: String }
  #             key   = a node id such as "6109" or "6109902000/80"
  #             label = description, including path context
  #   context:  {
  #     product: String,        # analysis summary + attributes + numeric facts +
  #                             # original description, max ~3000 chars
  #     path:    Array<String>, # descriptions chosen so far (chapter -> heading -> nodes)
  #     level:   Symbol,        # :chapter | :heading | :node
  #     chapter_note: String|nil
  #   }
  #
  #   returns: {
  #     key:           String,
  #     confidence:    Float (0..1),
  #     probabilities: { key => Float },
  #     reasoning:     String|nil,
  #     chooser:       String
  #   }
  #
  # Must never raise; on failure return nil.
  class Chooser
    def choose(question:, options:, context:)
      raise NotImplementedError
    end
  end
end
