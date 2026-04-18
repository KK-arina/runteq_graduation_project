# test/integration/dashboard_test.rb
# =============================================================
# ダッシュボード機能の統合テスト
# HTTP リクエストの流れを通して画面の内容・動作を検証する
# =============================================================
require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
  end

  # ---- ダッシュボードの基本表示テスト ----
  test "ダッシュボードに達成率サマリーが表示されること" do
    log_in_as(@user)
    get dashboard_path
    assert_response :success

    assert_select "h1", text: /ダッシュボード/

    # C-6 でビューの見出しを「今週の習慣達成率（月曜〜今日）」に変更したため
    # 正規表現を「今週の習慣達成率」に更新する。
    # /今週の達成率/ は「今週の習慣達成率」にもマッチするが、
    # より実際の文言に近い表現に修正しておく。
    assert_select "h2", text: /今週の習慣達成率/
    assert_select "h2", text: /今日の習慣チェック/
  end

  # ---- 習慣が0件の場合のEmpty State表示テスト ----
  test "習慣が0件のときEmpty Stateが表示されること" do
    @user.habits.update_all(deleted_at: Time.current)
    log_in_as(@user)
    get dashboard_path
    assert_response :success
    assert_select "p", text: /まだ習慣が登録されていません/
  end

  # ---- ルートパスからのリダイレクトテスト ----
  test "ログイン後にルートパスへアクセスするとダッシュボードにリダイレクトされること" do
    log_in_as(@user)
    get root_path
    assert_redirected_to dashboard_path
  end
end