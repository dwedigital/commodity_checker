# frozen_string_literal: true

require "test_helper"

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
end
