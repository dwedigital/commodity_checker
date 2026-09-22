module Classification
  # Turns the analysis into a shortlist of candidate 4-digit headings. It runs
  # the tariff search directly on each short search phrase (with the word-by-word
  # fallback OFF, since these phrases are already short noun phrases), takes the
  # heading of every hit, and unions those with every heading of the candidate
  # chapters. Search hits come first; the list is de-duplicated by heading.
  class CandidateRetriever
    def initialize(tariff_tree: nil, tariff_service: nil)
      @tariff_tree = tariff_tree || TariffTree.new
      @tariff_service = tariff_service || TariffLookupService.new
    end

    # Returns an ordered, de-duplicated Array of
    #   { code: "6109", description: "...", source: :search | :chapter }
    def retrieve(analysis)
      phrases = Array(analysis[:search_phrases]).map(&:to_s).reject(&:blank?)
      chapters = Array(analysis[:candidate_chapters]).map { |c| c.to_s.gsub(/\D/, "")[0, 2] }.reject(&:blank?)

      search_hits = collect_search_hits(phrases)
      heading_descriptions = heading_description_map(chapters, search_hits.keys)

      ordered = []
      seen = Set.new

      # Search hits first, best score first.
      search_hits.sort_by { |_code, hit| -hit[:score] }.each do |code, hit|
        next unless seen.add?(code)

        ordered << { code: code, description: heading_descriptions[code] || hit[:description], source: :search }
      end

      # Then every heading of each candidate chapter, in chapter order.
      chapters.each do |chapter|
        @tariff_tree.headings_for_chapter(chapter).each do |heading|
          code = heading[:code]
          next unless seen.add?(code)

          ordered << { code: code, description: heading[:description], source: :chapter }
        end
      end

      ordered
    end

    private

    # heading code => { description:, score: } keyed by best score across phrases.
    def collect_search_hits(phrases)
      hits = {}

      phrases.each do |phrase|
        results = @tariff_service.search(phrase, fallback: false)
        results.each do |result|
          code = result[:code].to_s.gsub(/\D/, "")
          next if code.length < 4

          heading = code[0, 4]
          score = result[:score].to_f
          existing = hits[heading]
          next if existing && existing[:score] >= score

          hits[heading] = { description: result[:description].to_s, score: score }
        end
      end

      hits
    end

    # Proper heading descriptions for the candidate chapters and for the chapters
    # the search hits fall in, so heading options read well for the chooser.
    def heading_description_map(candidate_chapters, hit_headings)
      chapters = (candidate_chapters + hit_headings.map { |h| h[0, 2] }).uniq
      map = {}

      chapters.each do |chapter|
        @tariff_tree.headings_for_chapter(chapter).each do |heading|
          map[heading[:code]] = heading[:description]
        end
      end

      map
    end
  end
end
