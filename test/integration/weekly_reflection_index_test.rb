# test/integration/weekly_reflection_index_test.rb
#
# 週次振り返り一覧ページの統合テスト
# Issue #21

require "test_helper"

class WeeklyReflectionIndexTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  # ===========================================================
  # 画面表示の統合テスト
  # ===========================================================
  test "一覧ページに今週の状況セクションが表示されること" do
    log_in_as(@user)
    get weekly_reflections_path

    assert_response :success
    # 「今週の状況」セクションが存在することを確認します
    assert_select "body", text: /今週の状況/
  end

  test "一覧ページに過去の振り返り履歴セクションが表示されること" do
    log_in_as(@user)
    get weekly_reflections_path

    assert_response :success
    assert_select "body", text: /過去の振り返り履歴/
  end

  test "過去の振り返りが0件の場合 Empty State が表示されること" do
    log_in_as(@user)

    # @user の振り返りを全削除してから確認します
    @user.weekly_reflections.destroy_all

    get weekly_reflections_path

    assert_response :success
    assert_select "body", text: /まだ振り返りがありません/
  end

  test "習慣が登録されている場合に達成率が表示されること" do
    log_in_as(@user)
    get weekly_reflections_path

    assert_response :success
    # 習慣が存在する場合、何らかの「%」表示があることを確認します
    # （テスト用の習慣データは fixtures から来ます）
    assert_select "body", text: /%/
  end
end
