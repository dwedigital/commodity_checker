require "test_helper"
require "minitest/mock"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "guests can start a lookup from the homepage" do
    get root_path
    assert_response :success
    assert_select "form[action=?][data-turbo-frame=lookup_result]", home_lookup_path do
      assert_select "label[for=url]"
      assert_select "input[type=url][required]"
    end
    assert_select "[data-lookup-limit-remaining-value='3']"
    assert_select "turbo-frame#lookup_result"
    assert_select "a[href^=?]", new_user_session_path, minimum: 1
  end

  test "exhausted guest allowance is passed to the limit controller" do
    GuestLookup.stub :count_for_token, 3 do
      get root_path
    end
    assert_response :success
    assert_select "[data-lookup-limit-limit-reached-value=true]"
    assert_select "[data-lookup-limit-target=limitReached] a[href^=?]", new_user_session_path
  end

  test "signed in homepage retains dashboard and lookup navigation" do
    sign_in users(:free_user)
    get root_path
    assert_response :success
    assert_select "[data-lookup-limit-authenticated-value=true]"
    assert_select "[data-remaining-wrapper]", count: 0
    assert_select "a[href=?]", dashboard_path, minimum: 1
    assert_select "a[href=?]", new_product_lookup_path(tab: "photo"), minimum: 1
  end

  test "empty lookup returns an error in the result frame" do
    post home_lookup_path, params: { url: "" }
    assert_response :success
    assert_select "turbo-frame#lookup_result", text: /Please enter a product URL/
  end

  test "successful lookup renders the product and suggested code" do
    scraper = Minitest::Mock.new
    scraper.expect :scrape, { status: :completed, title: "Cotton T-shirt", url: "https://example.com/shirt" }, [ "https://example.com/shirt" ]
    suggester = Minitest::Mock.new
    suggester.expect :suggest, { commodity_code: "6109100010", confidence: 0.9, reasoning: "Cotton knitted garment" }, [ "Cotton T-shirt" ]
    ProductScraperService.stub :new, scraper do
      LlmCommoditySuggester.stub :new, suggester do
        post home_lookup_path, params: { url: "https://example.com/shirt" }
      end
    end
    assert_response :success
    assert_select "turbo-frame#lookup_result", text: /6109100010/
    assert_select "h3", text: "Cotton T-shirt"
    scraper.verify
    suggester.verify
  end
end
