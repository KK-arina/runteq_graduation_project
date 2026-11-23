# test/integration/filter_parameter_logging_test.rb
require "test_helper"

# ログに残さないパラメータの設定（config/initializers/filter_parameter_logging.rb）を確認するテスト
class FilterParameterLoggingTest < ActiveSupport::TestCase
  # Rails が実際にログで使うのと同じ仕組み（ParameterFilter）で、設定を試す
  def filtered(params)
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
  end

  test "OAuth の code と state はログで隠される" do
    result = filtered("code" => "abc123", "state" => "xyz789")

    assert_equal "[FILTERED]", result["code"]
    assert_equal "[FILTERED]", result["state"]
  end

  test "名前に code や state を含むだけの項目は隠されない（完全一致の確認）" do
    result = filtered("country_code" => "JP", "statement" => "hello")

    assert_equal "JP", result["country_code"]
    assert_equal "hello", result["statement"]
  end

  test "もともと隠していた password は引き続き隠される" do
    result = filtered("password" => "secret-pass")

    assert_equal "[FILTERED]", result["password"]
  end
end
