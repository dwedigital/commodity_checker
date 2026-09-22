# frozen_string_literal: true

require "test_helper"

class Classification::ChoosersTest < ActiveSupport::TestCase
  def with_env(vars)
    saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "uses Jev with a Claude fallback when the TypeSafe key is configured" do
    with_env("TYPESAFE_API_KEY" => "test-key", "TARIFFIK_CHOOSER" => nil) do
      chooser = Classification::Choosers.default

      assert_instance_of Classification::JevChooser, chooser
      assert_instance_of Classification::ClaudeChooser, chooser.instance_variable_get(:@fallback)
    end
  end

  test "uses Claude when the TypeSafe key is missing" do
    with_env("TYPESAFE_API_KEY" => nil, "TARIFFIK_CHOOSER" => nil) do
      assert_instance_of Classification::ClaudeChooser, Classification::Choosers.default
    end
  end

  test "TARIFFIK_CHOOSER=claude forces Claude even with a key" do
    with_env("TYPESAFE_API_KEY" => "test-key", "TARIFFIK_CHOOSER" => "claude") do
      assert_instance_of Classification::ClaudeChooser, Classification::Choosers.default
    end
  end
end
