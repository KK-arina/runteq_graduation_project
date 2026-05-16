# test/controllers/sessions_controller_test.rb
#
# ==============================================================================
# SessionsController のテスト（E-4: ディープリンク対応）
# ==============================================================================
#
# 【このテストの役割】
#   E-4 で追加したディープリンク機能とセキュリティ対策（オープンリダイレクト防止）が
#   正しく動作することを自動テストで保証する。
#
# 【ActionDispatch::IntegrationTest とは】
#   実際のHTTPリクエスト（GET/POST）を模擬してコントローラーをテストするクラス。
#   ルーティング → コントローラー → レスポンスの流れ全体をテストできる。
#
# 【テストの実行方法】
#   docker compose exec web bin/rails test test/controllers/sessions_controller_test.rb
# ==============================================================================

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  # setup: 各テストの実行前に必ず呼ばれる準備処理
  # users(:one) は test/fixtures/users.yml の one エントリを参照する
  # パスワードは fixtures で BCrypt::Password.create('password', cost: 1) として設定済み
  setup do
    @user = users(:one)
  end

  # ============================================================
  # 正常系テスト（安全なリダイレクト）
  # ============================================================

  test "redirect_to なしでログインすると dashboard へ遷移する" do
    # 【テストの目的】
    #   E-4 の変更で従来の「redirect_to なしはダッシュボードへ」の動作が
    #   壊れていないことを確認する（デグレード防止）。
    post login_path, params: {
      session: { email: @user.email, password: "password" }
    }

    assert_redirected_to dashboard_path
  end

  test "安全なアプリ内パスを指定するとそのページへ遷移する" do
    # 【テストの目的】
    #   /habits のような安全なアプリ内パスを指定したとき、
    #   ログイン後にそのページへ遷移することを確認する。
    #
    # 【hidden_field_tag を使っているため redirect_to は POST params に含まれる】
    #   フォームの hidden_field_tag :redirect_to が POST body に含める設計のため、
    #   テストでも params の中に redirect_to を含める。
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "/habits"
    }

    assert_redirected_to "/habits"
  end

  test "クエリパラメータ付きのパスでも正しく遷移する" do
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "/tasks?tab=must"
    }

    assert_redirected_to "/tasks?tab=must"
  end

  test "weekly_reflections/new への遷移も正しく動作する" do
    # LINE通知のディープリンクとして最も使われるパスを明示的にテスト
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "/weekly_reflections/new"
    }

    assert_redirected_to "/weekly_reflections/new"
  end

  # ============================================================
  # セキュリティテスト（オープンリダイレクト防止）
  # ============================================================

  test "外部URL（http://）を redirect_to に指定すると dashboard へフォールバックする" do
    # 【テストの目的】
    #   オープンリダイレクト攻撃の最も基本的なパターンを防げるか確認する。
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "http://evil.com"
    }

    assert_redirected_to dashboard_path
  end

  test "外部URL（https://）を redirect_to に指定すると dashboard へフォールバックする" do
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "https://evil.com/phishing"
    }

    assert_redirected_to dashboard_path
  end

  test "ダブルスラッシュ始まりは dashboard へフォールバックする" do
    # 【テストの目的】
    #   //evil.com はブラウザによっては外部ホストとして解釈される。
    #   safe_redirect_path? のダブルスラッシュ対策（start_with?("//"）が
    #   機能しているか確認する。
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "//evil.com"
    }

    assert_redirected_to dashboard_path
  end

  test "javascript: スキームは dashboard へフォールバックする" do
    # 【テストの目的】
    #   javascript:alert(1) のような XSS 攻撃を拒否できるか確認する。
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: "javascript:alert(1)"
    }

    assert_redirected_to dashboard_path
  end

  test "空文字の redirect_to は dashboard へフォールバックする" do
    post login_path, params: {
      session: { email: @user.email, password: "password" },
      redirect_to: ""
    }

    assert_redirected_to dashboard_path
  end

  # ============================================================
  # ログイン失敗時のテスト
  # ============================================================

  test "パスワードが間違っていたらログイン画面を再表示する" do
    post login_path, params: {
      session: { email: @user.email, password: "wrong_password" }
    }

    # HTTP 422 が返ることを確認
    assert_response :unprocessable_entity
  end
end