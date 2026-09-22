# frozen_string_literal: true

require "test_helper"

module Classification
  class TariffTreeTest < ActiveSupport::TestCase
    API = "https://www.trade-tariff.service.gov.uk/api/v2"

    def setup
      @tree = TariffTree.new
    end

    # ---------------------------------------------------------------------------
    # chapters / headings_for_chapter
    # ---------------------------------------------------------------------------

    test "chapters returns two-digit code, item id and cleaned description" do
      stub_get("#{API}/chapters", {
        data: [
          { type: "chapter", attributes: { goods_nomenclature_item_id: "6100000000", formatted_description: "Articles of <b>apparel</b> &amp; clothing, knitted" } },
          { type: "chapter", attributes: { goods_nomenclature_item_id: "0100000000", formatted_description: "Live animals" } }
        ]
      })

      chapters = @tree.chapters

      assert_equal 2, chapters.size
      assert_equal "61", chapters.first[:code]
      assert_equal "6100000000", chapters.first[:item_id]
      assert_equal "Articles of apparel & clothing, knitted", chapters.first[:description]
    end

    test "headings_for_chapter selects heading rows only" do
      stub_get("#{API}/chapters/61", chapter_body(headings: [
        { goods_nomenclature_item_id: "6109000000", formatted_description: "T-shirts, singlets" },
        { goods_nomenclature_item_id: "6110000000", formatted_description: "Jerseys, pullovers" }
      ]))

      headings = @tree.headings_for_chapter("61")

      assert_equal %w[6109 6110], headings.map { |h| h[:code] }
      assert_equal "T-shirts, singlets", headings.first[:description]
    end

    test "chapter_note returns the note markdown" do
      stub_get("#{API}/chapters/61", chapter_body(headings: [], chapter_note: "1. This chapter does not cover..."))

      assert_equal "1. This chapter does not cover...", @tree.chapter_note("61")
    end

    # ---------------------------------------------------------------------------
    # tree_for_heading: nesting by indent, suffix 10/80 identity
    # ---------------------------------------------------------------------------

    test "tree_for_heading nests commodities by number_indents" do
      stub_get("#{API}/headings/6109", heading_body(item_id: "6109000000", commodities: [
        commodity("6109100000", "80", 1, false, "Of cotton"),
        commodity("6109100010", "80", 2, true,  "T-shirts"),
        commodity("6109100090", "80", 2, true,  "Other"),
        commodity("6109900000", "80", 1, false, "Of other textile materials"),
        commodity("6109902000", "80", 2, true,  "Of man-made fibres")
      ]))

      root = @tree.tree_for_heading("6109")

      assert_equal "6109000000", root.item_id
      assert_equal 2, root.children.size, "two indent-1 groups hang off the heading"

      cotton = root.children.first
      assert_equal "6109100000/80", cotton.id
      refute cotton.declarable
      assert_equal %w[6109100010/80 6109100090/80], cotton.children.map(&:id)
      assert cotton.children.first.declarable
      assert_equal "T-shirts", cotton.children.first.description
    end

    test "tree_for_heading keeps suffix 10 and 80 rows of the same item id distinct" do
      stub_get("#{API}/headings/2204", heading_body(item_id: "2204000000", commodities: [
        commodity("2204101100", "10", 1, false, "With a protected designation of origin"),
        commodity("2204101100", "80", 2, true,  "Champagne")
      ]))

      root = @tree.tree_for_heading("2204")

      group = root.children.first
      assert_equal "2204101100/10", group.id
      refute group.declarable
      assert_equal [ "2204101100/80" ], group.children.map(&:id)
      assert group.children.first.declarable
      assert_equal "Champagne", group.children.first.description
    end

    test "tree_for_heading treats an empty heading as its own leaf" do
      stub_get("#{API}/headings/8888", heading_body(item_id: "8888000000", commodities: []))

      root = @tree.tree_for_heading("8888")

      assert_empty root.children
      assert_equal "8888000000", root.item_id
    end

    test "tree_for_heading falls back to <heading>000000 when the API fails" do
      stub_request(:get, "#{API}/headings/9999").to_return(status: 500, body: "boom")

      root = @tree.tree_for_heading("9999")

      assert_empty root.children
      assert_equal "9999000000", root.item_id
    end

    # ---------------------------------------------------------------------------
    # failure handling + caching
    # ---------------------------------------------------------------------------

    test "never raises and returns empty on a connection failure" do
      stub_request(:get, "#{API}/chapters").to_raise(Faraday::ConnectionFailed.new("refused"))

      assert_equal [], @tree.chapters
    end

    test "caches each GET for the injected cache store" do
      tree = TariffTree.new(cache: ActiveSupport::Cache::MemoryStore.new)
      stub = stub_get("#{API}/chapters", { data: [] })

      2.times { tree.chapters }

      assert_requested(stub, times: 1)
    end

    private

    def stub_get(url, body)
      stub_request(:get, url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: body.to_json
      )
    end

    def chapter_body(headings:, chapter_note: nil)
      {
        data: { type: "chapter", attributes: { goods_nomenclature_item_id: "6100000000", formatted_description: "Apparel", chapter_note: chapter_note } },
        included: [ { type: "section", attributes: {} } ] +
          headings.map { |h| { type: "heading", attributes: h } }
      }
    end

    def heading_body(item_id:, commodities:)
      {
        data: { type: "heading", attributes: { goods_nomenclature_item_id: item_id, formatted_description: "Heading", declarable: false } },
        included: commodities
      }
    end

    def commodity(item_id, suffix, indents, declarable, description)
      {
        type: "commodity",
        attributes: {
          goods_nomenclature_item_id: item_id,
          producline_suffix: suffix,
          number_indents: indents,
          declarable: declarable,
          formatted_description: description
        }
      }
    end
  end
end
