require "test_helper"

class PublicPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "blog index lists published guides" do
    get blog_path

    assert_response :success
    assert_select "h1", text: "Commodity codes, explained."
    assert_select ".tf-post-list a[href=?]", blog_post_path("understanding-uk-commodity-codes")
  end

  test "blog post renders its content with a route back to the guides" do
    get blog_post_path("understanding-uk-commodity-codes")

    assert_response :success
    assert_select "article.tf-article h1"
    assert_select ".tf-article-body.tf-prose"
    assert_select "a[href=?]", blog_path, minimum: 1
  end

  %w[privacy terms].each do |page|
    test "#{page} contents links all point at a section on the page" do
      get public_send("#{page}_path")

      assert_response :success
      anchors = css_select(".tf-legal-toc a").map { |a| a["href"].delete_prefix("#") }
      ids = css_select(".tf-prose h2[id]").map { |h| h["id"] }
      assert anchors.any?
      assert_equal ids, anchors
      assert_select ".tf-page-description", text: "Last updated: 3 June 2026"
    end
  end

  test "extension consent asks to connect and posts the extension details" do
    sign_in users(:one)
    get extension_auth_path(extension_id: "ext_abc123", redirect_uri: "chrome-extension://#{'a' * 32}/callback/callback.html")

    assert_response :success
    assert_select "body.tf-auth-page"
    assert_select "form[action=?]", extension_auth_create_path do
      assert_select "input[type=hidden][name=extension_id][value=ext_abc123]"
      assert_select "input[type=hidden][name=redirect_uri]"
      assert_select "button[type=submit]", text: /Connect extension/
    end
  end

  test "extension callback confirms the connection" do
    get extension_auth_callback_path(code: "xyz")

    assert_response :success
    assert_select "h1", text: "Extension connected"
  end
end
