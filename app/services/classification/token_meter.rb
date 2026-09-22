module Classification
  # Optional, thread-local accounting for Claude token usage across a single
  # classification. It is off by default: ProductAnalyzer and ClaudeChooser call
  # +record+ on every Claude response, but nothing is stored unless a caller has
  # opened a +measure+ block. The eval rake task uses this to report tokens and
  # Claude calls per lookup; production code never touches it.
  module TokenMeter
    module_function

    # Runs the block with a fresh accumulator active and returns
    # [block_result, { input:, output:, calls: }].
    def measure
      previous = Thread.current[:classification_token_acc]
      acc = { input: 0, output: 0, calls: 0 }
      Thread.current[:classification_token_acc] = acc
      result = yield
      [ result, acc ]
    ensure
      Thread.current[:classification_token_acc] = previous
    end

    # Records one Claude call. No-op unless a measure block is active.
    def record(input:, output:)
      acc = Thread.current[:classification_token_acc]
      return unless acc

      acc[:input] += input.to_i
      acc[:output] += output.to_i
      acc[:calls] += 1
    end
  end
end
