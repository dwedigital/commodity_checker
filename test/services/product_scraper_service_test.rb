# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ProductScraperServiceTest < ActiveSupport::TestCase
  def setup
    @service = ProductScraperService.new
  end

  PAGE_URL = "https://www.etsy.com/uk/listing/1602240596/green-leaves-wallpaper"

  def extract_image(json_ld_image, og_image: nil)
    sources = { json_ld: { "image" => json_ld_image }, og: { image: og_image } }
    @service.send(:extract_and_normalize_image, sources, "", PAGE_URL)
  end

  # =============================================================================
  # JSON-LD image extraction
  # Regression: Etsy returns image as an ImageObject hash without a "url" key,
  # which previously crashed normalize_image_url with
  # "undefined method `start_with?' for an instance of Hash"
  # =============================================================================

  test "extracts image from plain string" do
    assert_equal "https://example.com/x.jpg", extract_image("https://example.com/x.jpg")
  end

  test "extracts image from array of strings" do
    assert_equal "https://example.com/y.jpg", extract_image([ "https://example.com/y.jpg" ])
  end

  test "extracts image from ImageObject hash with url key" do
    image = { "@type" => "ImageObject", "url" => "https://i.etsystatic.com/il.jpg" }
    assert_equal "https://i.etsystatic.com/il.jpg", extract_image(image)
  end

  test "extracts image from Etsy-style ImageObject hash with contentURL key" do
    image = { "@type" => "ImageObject", "contentURL" => "https://i.etsystatic.com/il_fullxfull.123.jpg" }
    assert_equal "https://i.etsystatic.com/il_fullxfull.123.jpg", extract_image(image)
  end

  test "extracts image from ImageObject hash with contentUrl key" do
    image = { "@type" => "ImageObject", "contentUrl" => "https://i.etsystatic.com/il.jpg" }
    assert_equal "https://i.etsystatic.com/il.jpg", extract_image(image)
  end

  test "extracts image from array of ImageObject hashes and normalizes protocol-relative URL" do
    image = [ { "@type" => "ImageObject", "url" => "//i.etsystatic.com/def.jpg" } ]
    assert_equal "https://i.etsystatic.com/def.jpg", extract_image(image)
  end

  test "falls back to og:image when ImageObject hash has no usable URL" do
    image = { "@type" => "ImageObject", "caption" => "no url here" }
    assert_equal "https://og.example.com/img.jpg", extract_image(image, og_image: "https://og.example.com/img.jpg")
  end

  test "returns nil when no image source is usable" do
    assert_nil extract_image({ "@type" => "ImageObject", "caption" => "no url here" })
    assert_nil extract_image(nil)
  end

  test "normalize_image_url returns nil for non-string input" do
    assert_nil @service.send(:normalize_image_url, { "url" => "https://example.com/x.jpg" }, PAGE_URL)
    assert_nil @service.send(:normalize_image_url, nil, PAGE_URL)
  end

  # =============================================================================
  # Scrape.do fallback chain
  # Regression: Scrape.do returns 502 when a site's bot protection (Etsy's
  # DataDome) defeats the standard datacenter proxy. 502 previously wasn't in
  # SUPER_FALLBACK_ERRORS, so the super proxy was never tried and Etsy lookups
  # always failed after ~60s.
  # =============================================================================

  LISTING_URL = "https://www.etsy.com/uk/listing/123/test-product"

  PRODUCT_HTML = <<~HTML
    <html><head>
      <title>Test Product</title>
      <meta property="og:title" content="Test Product">
      <meta property="og:image" content="https://i.etsystatic.com/il.jpg">
      <script type="application/ld+json">
        {"@type": "Product", "name": "Test Product", "description": "A lovely test product", "brand": {"name": "TestBrand"}}
      </script>
    </head><body>Test Product</body></html>
  HTML

  def with_scrape_do_configured(&block)
    ScrapeDoClient.stub(:api_token, "test-token") do
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new, &block)
    end
  end

  def stub_direct_fetch_blocked
    stub_request(:get, LISTING_URL).to_return(status: 403, body: "blocked")
  end

  def stub_standard_proxy(status:, body: "")
    stub_request(:get, "https://api.scrape.do/")
      .with(query: hash_including("url" => LISTING_URL))
      .to_return(status: status, body: body)
  end

  def stub_super_proxy(status:, body: "")
    stub_request(:get, "https://api.scrape.do/")
      .with(query: hash_including("url" => LISTING_URL, "super" => "true"))
      .to_return(status: status, body: body)
  end

  test "falls back to super proxy when standard proxy returns 502" do
    with_scrape_do_configured do
      stub_direct_fetch_blocked
      stub_standard_proxy(status: 502)
      super_stub = stub_super_proxy(status: 200, body: PRODUCT_HTML)

      result = @service.scrape(LISTING_URL)

      assert_requested super_stub
      refute_equal :failed, result[:status]
      assert_equal :scrape_do_super, result[:fetched_via]
      assert_equal "Test Product", result[:title]
    end
  end

  test "remembers retailer needs super proxy after super proxy rescue" do
    with_scrape_do_configured do
      stub_direct_fetch_blocked
      stub_standard_proxy(status: 502)
      stub_super_proxy(status: 200, body: PRODUCT_HTML)

      @service.scrape(LISTING_URL)

      assert @service.send(:requires_super_proxy?, "etsy")
    end
  end

  test "skips direct fetch and standard proxy for learned super proxy retailers" do
    with_scrape_do_configured do
      Rails.cache.write("#{ProductScraperService::SUPER_PROXY_CACHE_PREFIX}etsy", true)
      super_stub = stub_super_proxy(status: 200, body: PRODUCT_HTML)

      result = @service.scrape(LISTING_URL)

      assert_requested super_stub
      assert_not_requested :get, LISTING_URL
      assert_equal :scrape_do_super, result[:fetched_via]
      assert_equal [ "super_proxy" ], result[:fetch_attempts].map { |a| a[:method] }
    end
  end

  test "reports failure when super proxy also fails" do
    with_scrape_do_configured do
      stub_direct_fetch_blocked
      stub_standard_proxy(status: 502)
      stub_super_proxy(status: 502)

      result = @service.scrape(LISTING_URL)

      assert_equal :failed, result[:status]
      assert_match(/Scrape.do HTTP 502/, result[:error])
    end
  end
end
