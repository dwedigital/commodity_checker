# frozen_string_literal: true

require "test_helper"

module Classification
  class CandidateRetrieverTest < ActiveSupport::TestCase
    # Records the fallback kwarg so we can prove short phrases skip the
    # word-by-word fallback, and returns canned results per phrase.
    class FakeSearchService
      attr_reader :calls

      def initialize(responses)
        @responses = responses
        @calls = []
      end

      def search(query, fallback: true)
        @calls << { query: query, fallback: fallback }
        @responses[query] || []
      end
    end

    class FakeTree
      def initialize(headings)
        @headings = headings
      end

      def headings_for_chapter(two_digit)
        @headings[two_digit] || []
      end
    end

    test "unions search headings (first, by score) with candidate-chapter headings" do
      service = FakeSearchService.new(
        "knitted t-shirt" => [ { code: "6109100010", description: "leaf desc a", score: 90 } ],
        "polyester top"   => [ { code: "6110200000", description: "leaf desc b", score: 70 } ]
      )
      tree = FakeTree.new(
        "61" => [
          { code: "6109", description: "T-shirts, singlets, knitted" },
          { code: "6110", description: "Jerseys, pullovers, knitted" },
          { code: "6111", description: "Babies garments, knitted" }
        ]
      )
      retriever = CandidateRetriever.new(tariff_tree: tree, tariff_service: service)

      candidates = retriever.retrieve(
        search_phrases: [ "knitted t-shirt", "polyester top" ],
        candidate_chapters: [ "61" ]
      )

      assert_equal %w[6109 6110 6111], candidates.map { |c| c[:code] }
      assert_equal %i[search search chapter], candidates.map { |c| c[:source] }
      # Heading description is preferred over the search hit's leaf description.
      assert_equal "T-shirts, singlets, knitted", candidates.first[:description]
    end

    test "runs every phrase search with the fallback disabled" do
      service = FakeSearchService.new("electric kettle" => [])
      tree = FakeTree.new("85" => [])
      retriever = CandidateRetriever.new(tariff_tree: tree, tariff_service: service)

      retriever.retrieve(search_phrases: [ "electric kettle" ], candidate_chapters: [ "85" ])

      assert service.calls.any?
      assert(service.calls.all? { |c| c[:fallback] == false })
    end

    test "returns an empty list when nothing matches and no chapters given" do
      service = FakeSearchService.new("mystery object" => [])
      tree = FakeTree.new({})
      retriever = CandidateRetriever.new(tariff_tree: tree, tariff_service: service)

      assert_equal [], retriever.retrieve(search_phrases: [ "mystery object" ], candidate_chapters: [])
    end
  end
end
