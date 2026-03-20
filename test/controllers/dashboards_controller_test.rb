# test/controllers/dashboards_controller_test.rb
# =============================================================
# DashboardsController のコントローラーテスト
#
# ⚠ Rails 7 では assigns(:インスタンス変数名) は使用不可
#   （rails-controller-testing gem なしでは動かない）
#   代わりに assert_select でHTMLの内容を検証する方法を使う
#   → これが「レスポンスの内容でテストする」Rails 7 推奨スタイル
# =============================================================

require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  # setup : 各テストの前に実行される準備メソッド
  # fixturesから共通で使うデータを取得しておく
  def setup
    @user = users(:one)
  end

  # ---- 未ログイン時のアクセス制御テスト ----
  test "未ログイン時はログインページにリダイレクトされること" do
    get dashboard_path
    # assert_redirected_to : 指定パスへのリダイレクトが発生したか確認
    assert_redirected_to login_path
  end

  # ---- ログイン後の表示テスト ----
  # assigns を使わず assert_select でHTMLの内容を検証する
  test "ログイン後にダッシュボードが表示され必要な情報が存在すること" do
    # TestLoginHelper の log_in_as を使ってログイン
    # ここを変えるだけでアプリ全体のテストログイン方法を一括変更できる
    log_in_as(@user)

    get dashboard_path
    # assert_response :success : HTTPステータス 200 OK を確認
    assert_response :success

    # assert_select でHTMLに要素が存在するかを確認する
    # assigns(:today) などは使わず「画面に表示されている内容」で検証する
    assert_select "h1", text: /ダッシュボード/
    assert_select "h2", text: /今週の達成率/
    assert_select "h2", text: /今日の習慣チェック/
  end

  # ---- ルートパスからのリダイレクトテスト ----
  test "ログイン済みでルートパスにアクセスするとダッシュボードにリダイレクトされること" do
    log_in_as(@user)

    get root_path
    assert_redirected_to dashboard_path
  end
end
