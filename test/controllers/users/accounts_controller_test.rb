require "test_helper"

# The account page had no coverage at all, which is how it came to render a
# partial that was never committed: the suite stayed green while
# /dashboard/account raised a missing template. These render it.
class Users::AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @user = users(:one)
    sign_in @user
  end

  test "the account page renders" do
    get account_path

    assert_response :success
    assert_select ".tf-settings-email", text: @user.email
  end

  test "the account page shows the Google profile photo when there is one" do
    @user.update!(avatar_url: "https://lh3.googleusercontent.com/a/avatar")

    get account_path

    assert_response :success
    assert_select "img.tf-account-avatar[src=?]", "https://lh3.googleusercontent.com/a/avatar"
  end

  test "the account page falls back to an initial without a Google photo" do
    @user.update!(avatar_url: nil)

    get account_path

    assert_response :success
    assert_select "img.tf-account-avatar", count: 0
    assert_select "span.tf-account-avatar", text: @user.display_name.first.upcase
  end

  test "the account page needs a signed-in user" do
    sign_out @user

    get account_path

    assert_redirected_to new_user_session_path
  end

  test "closing the account deletes the user" do
    assert_difference -> { User.count }, -1 do
      delete account_path
    end

    assert_redirected_to root_path
  end
end
