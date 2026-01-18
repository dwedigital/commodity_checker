require "test_helper"

class ProductLookupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @free_user = users(:free_user)
    @starter_user = users(:one)
  end

  # Lookup limit enforcement tests

  test "free user can create lookup when under limit" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    assert_difference("ProductLookup.count", 1) do
      post product_lookups_path, params: { product_lookup: { url: "https://www.amazon.co.uk/dp/TEST123" } }
    end

    assert_response :redirect
  end

  test "free user is blocked when at limit" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    # Create 5 lookups to hit the limit
    5.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert_no_difference("ProductLookup.count") do
      post product_lookups_path, params: { product_lookup: { url: "https://www.amazon.co.uk/dp/BLOCKED" } }
    end

    assert_redirected_to product_lookups_path
    assert_match(/monthly lookup limit/, flash[:alert])
  end

  test "starter user is not blocked regardless of lookup count" do
    sign_in @starter_user
    @starter_user.product_lookups.destroy_all

    # Create 10 lookups to exceed free limit
    10.times do |i|
      @starter_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    assert_difference("ProductLookup.count", 1) do
      post product_lookups_path, params: { product_lookup: { url: "https://www.amazon.co.uk/dp/TEST456" } }
    end

    assert_response :redirect
    assert_nil flash[:alert]
  end

  test "guest user bypass limit check and uses quick_lookup" do
    # Guest users should use quick_lookup which doesn't check the limit
    assert_no_difference("ProductLookup.count") do
      post product_lookups_path, params: { product_lookup: { url: "https://www.amazon.co.uk/dp/GUEST" } }
    end

    # Should render the quick_result view (not get blocked)
    assert_response :success
  end

  test "photo lookup is blocked when free user at limit" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    # Create 5 lookups to hit the limit
    5.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    # Create a test image file
    image = fixture_file_upload(Rails.root.join("test/fixtures/files/test_image.png"), "image/png")

    assert_no_difference("ProductLookup.count") do
      post create_from_photo_product_lookups_path, params: { product_lookup: { product_image: image } }
    end

    assert_redirected_to product_lookups_path
    assert_match(/monthly lookup limit/, flash[:alert])
  end

  test "index view shows remaining lookups for free user" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    2.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    get product_lookups_path

    assert_response :success
    assert_select "span.font-semibold", text: "3 of 5"
  end

  test "index view shows limit reached message when at limit" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    5.times do |i|
      @free_user.product_lookups.create!(url: "https://example.com/#{i}", scrape_status: :completed)
    end

    get product_lookups_path

    assert_response :success
    assert_match(/used all/, response.body)
  end

  test "index view does not show limit banner for premium user" do
    sign_in @starter_user

    get product_lookups_path

    assert_response :success
    refute_match(/free lookups remaining/, response.body)
  end

  test "new view shows limit indicator for free user" do
    sign_in @free_user
    @free_user.product_lookups.destroy_all

    get new_product_lookup_path

    assert_response :success
    assert_match(/5 of 5/, response.body)
  end
end
