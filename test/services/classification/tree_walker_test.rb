# frozen_string_literal: true

require "test_helper"

module Classification
  class TreeWalkerTest < ActiveSupport::TestCase
    # Fake tariff tree: canned chapters, headings, commodity trees and notes.
    class FakeTree
      def initialize(chapters: [], headings: {}, trees: {}, notes: {})
        @chapters = chapters
        @headings = headings
        @trees = trees
        @notes = notes
      end

      def chapters = @chapters
      def headings_for_chapter(two_digit) = @headings[two_digit] || []
      def chapter_note(two_digit) = @notes[two_digit]

      def tree_for_heading(four_digit)
        @trees[four_digit] || TariffTree::Node.new(
          id: "#{four_digit}000000/root", item_id: "#{four_digit}000000",
          suffix: nil, indent: -1, declarable: false, grouping: true,
          description: "", children: []
        )
      end
    end

    class FakeService
      def initialize(commodities) = (@commodities = commodities)
      def get_commodity(code) = @commodities[code]
    end

    # Always picks the first option offered, with a fixed confidence.
    class FirstChooser < Chooser
      def initialize(confidence: 0.9) = (@confidence = confidence)

      def choose(question:, options:, context:)
        key = options.first[:key]
        { key: key, confidence: @confidence, probabilities: { key => @confidence }, reasoning: "first", chooser: "fake" }
      end
    end

    # Low confidence on the candidate-heading step (path empty), normal elsewhere,
    # forcing the walk into the chapter route.
    class ChapterFallbackChooser < Chooser
      def choose(question:, options:, context:)
        key = options.first[:key]
        conf = (context[:level] == :heading && Array(context[:path]).empty?) ? 0.2 : 0.9
        { key: key, confidence: conf, probabilities: { key => conf }, reasoning: "x", chooser: "fake" }
      end
    end

    def analysis
      { product_summary: "A knitted cotton t-shirt", attributes: { material: "cotton" }, numeric_facts: [], candidate_chapters: [ "61" ], original_description: "knitted cotton t-shirt" }
    end

    def node(item_id, indent, declarable, description, children: [])
      TariffTree::Node.new(
        id: "#{item_id}/80", item_id: item_id, suffix: "80", indent: indent,
        declarable: declarable, grouping: false, description: description, children: children
      )
    end

    def root_for(item_id, children)
      TariffTree::Node.new(id: "#{item_id}/root", item_id: item_id, suffix: nil, indent: -1, declarable: false, grouping: true, description: "Heading", children: children)
    end

    test "walks candidate heading down to a declarable leaf" do
      tshirts = node("6109100010", 2, true, "T-shirts")
      other = node("6109100090", 2, true, "Other")
      cotton = node("6109100000", 1, false, "Of cotton", children: [ tshirts, other ])
      tree = FakeTree.new(
        chapters: [ { code: "61", item_id: "6100000000", description: "Apparel" } ],
        trees: { "6109" => root_for("6109000000", [ cotton ]) }
      )
      service = FakeService.new("6109100010" => { code: "6109100010", description: "T-shirts", duty_rate: "12%" })
      walker = TreeWalker.new(tariff_tree: tree, tariff_service: service)

      result = walker.walk(
        analysis: analysis,
        candidates: [ { code: "6109", description: "T-shirts, knitted", source: :search } ],
        chooser: FirstChooser.new
      )

      assert_equal "6109100010", result[:commodity_code]
      assert_equal true, result[:validated]
      assert_equal "Apparel", result[:category]
      assert_equal "T-shirts", result[:official_description]
      assert_in_delta 0.729, result[:confidence], 0.0001
      assert_equal %i[heading node node], result[:steps].map { |s| s[:level] }
      assert_includes result[:path], "Of cotton"
      assert_includes result[:path], "T-shirts"
    end

    test "falls back to the chapter route when the heading confidence is low" do
      leaf = node("8516108090", 1, true, "Other")
      tree = FakeTree.new(
        chapters: [ { code: "85", item_id: "8500000000", description: "Electrical machinery" } ],
        headings: { "85" => [ { code: "8516", description: "Electric heaters, kettles" } ] },
        trees: { "8516" => root_for("8516000000", [ leaf ]) }
      )
      service = FakeService.new("8516108090" => { code: "8516108090", description: "Other", duty_rate: "2.7%" })
      walker = TreeWalker.new(tariff_tree: tree, tariff_service: service)

      result = walker.walk(
        analysis: analysis.merge(candidate_chapters: [ "85" ]),
        candidates: [ { code: "6109", description: "wrong heading", source: :search } ],
        chooser: ChapterFallbackChooser.new
      )

      assert_equal "8516108090", result[:commodity_code]
      levels = result[:steps].map { |s| s[:level] }
      assert_includes levels, :chapter, "the chapter route was taken"
      assert_equal :heading, levels.first, "the low-confidence candidate heading step is recorded first"
      assert_equal "Electrical machinery", result[:category]
      # heading(0.9) * chapter-route heading(0.9) * node(0.9); the rejected 0.2 is excluded
      assert_in_delta 0.729, result[:confidence], 0.0001
    end

    test "stops at the depth cap on a pathological tree" do
      # 15 nested non-declarable nodes; the walk must stop at MAX_DEPTH (12).
      leaf = node("9999999915", 15, false, "n15")
      chain = (14).downto(1).reduce(leaf) do |child, i|
        node("99999999#{format('%02d', i)}", i, false, "n#{i}", children: [ child ])
      end
      tree = FakeTree.new(
        chapters: [ { code: "99", item_id: "9900000000", description: "Chap 99" } ],
        trees: { "9999" => root_for("9999000000", [ chain ]) }
      )
      walker = TreeWalker.new(tariff_tree: tree, tariff_service: FakeService.new({}))

      result = walker.walk(
        analysis: analysis.merge(candidate_chapters: [ "99" ]),
        candidates: [ { code: "9999", description: "deep", source: :search } ],
        chooser: FirstChooser.new
      )

      node_steps = result[:steps].count { |s| s[:level] == :node }
      assert_equal TreeWalker::MAX_DEPTH, node_steps
      assert_equal "9999999912", result[:commodity_code]
    end

    test "returns nil when the chooser cannot decide" do
      null_chooser = Class.new(Chooser) { def choose(**) = nil }.new
      tree = FakeTree.new(chapters: [ { code: "61", item_id: "6100000000", description: "Apparel" } ])
      walker = TreeWalker.new(tariff_tree: tree, tariff_service: FakeService.new({}))

      assert_nil walker.walk(analysis: analysis, candidates: [], chooser: null_chooser)
    end
  end
end
