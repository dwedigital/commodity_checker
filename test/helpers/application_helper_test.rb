require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "commodity_code_display splits a ten-digit code into heading, subheading and national digits" do
    assert_dom_equal "6109 <span>10</span> 0010", commodity_code_display("6109100010")
  end

  test "commodity_code_display handles eight and six digit codes" do
    assert_dom_equal "6109 <span>10</span> 00", commodity_code_display("61091000")
    assert_dom_equal "6109 <span>10</span>", commodity_code_display("610910")
  end

  test "commodity_code_display leaves short or blank codes untouched" do
    assert_equal "6109", commodity_code_display("6109")
    assert_equal "", commodity_code_display(nil)
  end

  test "order_status_badge uses sentence case labels" do
    assert_dom_equal '<span class="tf-badge tf-badge-muted">In transit</span>', order_status_badge(Order.new(status: :in_transit))
  end

  test "lookup_status_badge returns nothing when the lookup has no status" do
    lookup = ProductLookup.new
    lookup.scrape_status = nil
    assert_nil lookup_status_badge(lookup)
  end
end
