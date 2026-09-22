# Suggests a UK 10-digit commodity code for a product description.
#
# The default pipeline is retrieve-then-walk (Classification::*): one Claude call
# turns the description into structured facts and short search phrases, those
# phrases and the candidate chapters produce a shortlist of real headings, and a
# chooser walks the real tariff tree from a heading down to a declarable leaf.
# This replaces the old single-shot "ask Claude for a code" approach, which is
# still available as LegacyCommoditySuggester (set TARIFFIK_PIPELINE=legacy).
#
# Public contract (unchanged, relied on by jobs, controllers and services):
#   #suggest(description) ->
#     nil                          for blank input or a pipeline failure
#     Hash with symbol keys:
#       :commodity_code       10 digits, no spaces
#       :confidence           Float 0..1
#       :reasoning            String (shown in the UI via CommoditySuggestionFormatter)
#       :category             String
#       :validated            Boolean
#       :official_description String or nil
#       :duty_rate            String or nil
#   (the pipeline also adds :path and :steps, which callers ignore)
#
# Never raises.
class LlmCommoditySuggester
  # Collaborators are injectable for tests; production uses the defaults.
  def initialize(analyzer: nil, chooser: nil, tariff_tree: nil, tariff_service: nil)
    @analyzer = analyzer
    @chooser = chooser
    @tariff_tree = tariff_tree
    @tariff_service = tariff_service
  end

  def suggest(product_description)
    return nil if product_description.blank?
    return LegacyCommoditySuggester.new.suggest(product_description) if legacy_pipeline?

    run_pipeline(product_description)
  rescue => e
    Rails.logger.error("LLM commodity suggestion failed: #{e.message}")
    nil
  end

  private

  def legacy_pipeline?
    ENV["TARIFFIK_PIPELINE"] == "legacy"
  end

  def run_pipeline(product_description)
    analysis = analyzer.analyze(product_description)
    return nil unless analysis

    # The walker's product context includes the raw description alongside the
    # analyzer's structured facts.
    analysis[:original_description] = product_description

    candidates = candidate_retriever.retrieve(analysis)
    result = tree_walker.walk(analysis: analysis, candidates: candidates, chooser: chooser)
    return nil unless result && result[:commodity_code].present?

    result
  end

  def analyzer
    @analyzer ||= Classification::ProductAnalyzer.new
  end

  def chooser
    @chooser ||= Classification::Choosers.default
  end

  def tariff_service
    @tariff_service ||= TariffLookupService.new
  end

  def tariff_tree
    @tariff_tree ||= Classification::TariffTree.new
  end

  def candidate_retriever
    Classification::CandidateRetriever.new(tariff_tree: tariff_tree, tariff_service: tariff_service)
  end

  def tree_walker
    Classification::TreeWalker.new(tariff_tree: tariff_tree, tariff_service: tariff_service)
  end
end
