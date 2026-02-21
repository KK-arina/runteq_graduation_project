# test/integration/weekly_reflection_create_test.rb
#
# 【このファイルの役割】
# 振り返り作成フロー全体を E2E でテストする。
# ログイン → フォーム表示 → 入力 → 保存 → 一覧ページ確認

require "test_helper"

class WeeklyReflectionCreateTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "ログイン後に振り返りを作成して一覧ページへリダイレクトされること" do
    # 日曜AM5:00（振り返り可能な時間帯）に固定
    # この週の week_start_date = 2026-02-16（fixtures と重複しない）
    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      log_in_as(@user)

      # フォームページが表示されること
      get new_weekly_reflection_path
      assert_response :success

      # フォームを送信して保存
      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment: "今週は筋トレを3日しかできなかった。残業が多かった。"
        }
      }

      # 保存成功 → 一覧へリダイレクト
      assert_redirected_to weekly_reflections_path
    end
  end

  test "振り返りコメントが1001文字以上の場合はバリデーションエラーになること" do
    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      log_in_as(@user)

      # 1001文字（上限1000文字を超える）
      over_limit_comment = "あ" * 1001

      # カウントが増えないことを確認
      assert_no_difference "WeeklyReflection.count" do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: over_limit_comment }
        }
      end

      # バリデーションエラーで 422 が返ること
      # ※ このテストが通るには WeeklyReflection モデルに
      #   validates :reflection_comment, length: { maximum: 1000 } が必要
      assert_response :unprocessable_entity
    end
  end
end