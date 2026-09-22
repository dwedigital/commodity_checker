module Classification
  # Selects the Chooser implementation the pipeline should use.
  #
  # Jev (TypeSafe AI) is the default whenever TYPESAFE_API_KEY is configured: it
  # matched the Claude chooser's accuracy on the rulings eval at about half the
  # latency and a fraction of the Claude tokens. ClaudeChooser is always its
  # fallback for numeric-threshold levels, where Jev is documented as weak, and
  # is used outright when the key is missing or TARIFFIK_CHOOSER=claude is set.
  module Choosers
    module_function

    def default
      claude = ClaudeChooser.new
      return claude if ENV["TARIFFIK_CHOOSER"] == "claude"
      return claude unless defined?(Classification::JevChooser) && JevClient.new.configured?

      Classification::JevChooser.new(fallback: claude)
    end
  end
end
