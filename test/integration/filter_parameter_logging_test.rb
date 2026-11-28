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

  # ============================================================
  # 利用者が入力した文章
  # ============================================================

  test "振り返りの入力欄は隠され、気分の数値は残る" do
    # 実際のフォームと同じく weekly_reflection の中に入れて送られる形で試す
    result = filtered(
      "weekly_reflection" => {
        "reflection_comment"   => "今週の感想",
        "direct_reason"        => "できなかった理由",
        "background_situation" => "その背景",
        "next_action"          => "次の行動",
        "mood"                 => "4"
      }
    )
    reflection = result["weekly_reflection"]

    %w[reflection_comment direct_reason background_situation next_action].each do |key|
      assert_equal "[FILTERED]", reflection[key], "#{key} が隠されていない"
    end
    assert_equal "4", reflection["mood"]
  end

  test "PMVV の入力欄は隠され、まとまり（user_purpose）ごと消えてはいない" do
    result = filtered(
      "user_purpose" => {
        "purpose"           => "目的",
        "mission"           => "使命",
        "vision"            => "将来像",
        "value"             => "大切にしていること",
        "current_situation" => "今の状況"
      }
    )

    # 親の user_purpose は Hash のまま（部分一致で丸ごと隠れていない）
    assert_kind_of Hash, result["user_purpose"]

    %w[purpose mission vision value current_situation].each do |key|
      assert_equal "[FILTERED]", result["user_purpose"][key], "#{key} が隠されていない"
    end
  end

  test "習慣の名前・タスクの題名・メモ・休息モードの理由は隠され、目標回数は残る" do
    result = filtered(
      "habit"        => { "name" => "朝のジョギング", "weekly_target" => "5" },
      "task"         => { "title" => "資料を作る" },
      "memo"         => "今日のメモ",
      "user_setting" => { "rest_mode_reason" => "休む理由" }
    )

    assert_equal "[FILTERED]", result["habit"]["name"]
    assert_equal "5", result["habit"]["weekly_target"]
    assert_equal "[FILTERED]", result["task"]["title"]
    assert_equal "[FILTERED]", result["memo"]
    assert_equal "[FILTERED]", result["user_setting"]["rest_mode_reason"]
  end

  test "名前の一部が同じだけの項目は隠されない（入力欄の完全一致の確認）" do
    result = filtered(
      "numeric_value"   => "30",
      "user_purpose_id" => "12",
      "device_name"     => "iPhone",
      "subtitle"        => "sub"
    )

    assert_equal "30", result["numeric_value"]
    assert_equal "12", result["user_purpose_id"]
    assert_equal "iPhone", result["device_name"]
    assert_equal "sub", result["subtitle"]
  end
end
