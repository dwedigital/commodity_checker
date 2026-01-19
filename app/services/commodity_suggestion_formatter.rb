# Formats commodity code suggestion results for display
# Centralizes the formatting logic used across jobs
class CommoditySuggestionFormatter
  # Build a human-readable reasoning string from a suggestion hash
  # @param suggestion [Hash] The suggestion from LlmCommoditySuggester
  # @return [String] Formatted reasoning string
  def self.build_reasoning(suggestion)
    return "" unless suggestion

    parts = []
    parts << suggestion[:reasoning] if suggestion[:reasoning].present?
    parts << "Category: #{suggestion[:category]}" if suggestion[:category].present?
    parts << "Official: #{suggestion[:official_description]}" if suggestion[:official_description].present?
    parts << "(Validated)" if suggestion[:validated]
    parts << "(Unvalidated - code may need verification)" if suggestion[:validated] == false

    parts.join(" | ")
  end
end
