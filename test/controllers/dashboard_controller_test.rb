require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the dashboard tells a signed-in user how to connect an AI assistant" do
    sign_in users(:free_user)

    get dashboard_path

    assert_response :success
    assert_select "#mcp" do
      assert_select "h2", text: "Connect an AI assistant"
      assert_select "code", text: /claude mcp add --transport http tariffik http:\/\/www\.example\.com\/mcp/
    end
  end

  test "a free account is told MCP lookups come out of its monthly allowance" do
    # The allowance is shared, so the dashboard should not imply MCP is extra.
    user = users(:free_user)
    user.product_lookups.create!(url: "https://example.com/a", lookup_type: :url)
    sign_in user

    get dashboard_path

    assert_select "#mcp", text: /come out of your #{User::FREE_MONTHLY_LOOKUP_LIMIT} a month/
    assert_select "#mcp", text: /You have #{user.lookups_remaining} left/
  end

  test "a paid account is not shown the free allowance note" do
    sign_in users(:one) # starter

    get dashboard_path

    assert_response :success
    assert_select "#mcp"
    assert_select "#mcp", { text: /come out of your/, count: 0 }
  end

  test "the dashboard needs a signed-in user" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end
end
