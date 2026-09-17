require "test_helper"

class ExtensionAuthControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  CHROME_ID = "gkjpgbgongkgdjfapjclandjhglnpmpn".freeze
  CALLBACK = "chrome-extension://#{CHROME_ID}/callback/callback.html".freeze

  def setup
    @user = users(:one)
    sign_in @user
    @original_chrome_id = ENV["CHROME_EXTENSION_ID"]
    ENV.delete("CHROME_EXTENSION_ID")
  end

  def teardown
    @original_chrome_id ? ENV["CHROME_EXTENSION_ID"] = @original_chrome_id : ENV.delete("CHROME_EXTENSION_ID")
  end

  test "consent screen renders for the extension's own callback page" do
    get extension_auth_path(extension_id: "ext_abc", redirect_uri: CALLBACK)

    assert_response :success
    assert_select "input[type=hidden][name=redirect_uri][value=?]", CALLBACK
  end

  # Google is the identity now, so the consent screen names the Google account
  # rather than showing an email initial and nothing else.
  test "consent screen names the Google account being connected" do
    get extension_auth_path(extension_id: "ext_abc", redirect_uri: CALLBACK)

    assert_response :success
    assert_select ".tf-consent-account strong", text: @user.display_name
    assert_select ".tf-consent-account span", text: @user.email
  end

  test "consent screen shows the Google profile photo when there is one" do
    @user.update!(avatar_url: "https://lh3.googleusercontent.com/a/avatar")

    get extension_auth_path(extension_id: "ext_abc", redirect_uri: CALLBACK)

    assert_select "img.tf-account-avatar[src=?]", "https://lh3.googleusercontent.com/a/avatar"
  end

  test "consent screen falls back to an initial without a Google photo" do
    @user.update!(avatar_url: nil)

    get extension_auth_path(extension_id: "ext_abc", redirect_uri: CALLBACK)

    assert_select "img.tf-account-avatar", count: 0
    assert_select "span.tf-account-avatar", text: @user.display_name.first.upcase
  end

  test "consent screen is refused when the code would be sent to another site" do
    [
      "https://evil.example/steal",
      "http://#{CHROME_ID}/callback/callback.html",
      "chrome-extension://#{CHROME_ID}/other.html",
      "chrome-extension://#{CHROME_ID}/callback/callback.html?next=https://evil.example",
      "chrome-extension://evil.example@#{CHROME_ID}/callback/callback.html",
      "chrome-extension://not-a-chrome-id/callback/callback.html",
      "javascript:alert(1)"
    ].each do |redirect_uri|
      get extension_auth_path(extension_id: "ext_abc", redirect_uri: redirect_uri)

      assert_redirected_to root_path, "expected #{redirect_uri} to be rejected"
      assert_match(/didn’t come from the Tariffik extension/, flash[:alert])
    end
  end

  test "connecting redirects the code to the extension callback" do
    assert_difference -> { @user.extension_auth_codes.count }, 1 do
      post extension_auth_create_path, params: { extension_id: "ext_abc", redirect_uri: CALLBACK }
    end

    assert_response :redirect
    assert_match %r{\Achrome-extension://#{CHROME_ID}/callback/callback\.html\?code=.+\z}, response.location
  end

  test "connecting with a foreign redirect creates no code and does not leave the site" do
    assert_no_difference -> { ExtensionAuthCode.count } do
      post extension_auth_create_path, params: { extension_id: "ext_abc", redirect_uri: "https://evil.example/steal" }
    end

    assert_redirected_to root_path
  end

  test "connecting without a redirect shows the code to copy manually" do
    post extension_auth_create_path, params: { extension_id: "ext_abc", redirect_uri: "" }

    assert_response :success
    assert_select ".tf-forward-copy code", text: /.+/
  end

  test "a configured Chrome extension ID pins the callback to that extension" do
    ENV["CHROME_EXTENSION_ID"] = CHROME_ID
    other = "chrome-extension://#{'a' * 32}/callback/callback.html"

    get extension_auth_path(extension_id: "ext_abc", redirect_uri: other)
    assert_redirected_to root_path

    get extension_auth_path(extension_id: "ext_abc", redirect_uri: CALLBACK)
    assert_response :success
  end
end
