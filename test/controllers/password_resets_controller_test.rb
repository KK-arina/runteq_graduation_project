# test/controllers/password_resets_controller_test.rb
#
# ==============================================================================
# PasswordResetsController の統合テスト
# ==============================================================================
#
# 【テスト実行コマンド】
#   docker compose exec web bin/rails test test/controllers/password_resets_controller_test.rb
# ==============================================================================
require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    # テスト間の干渉を防ぐため既存トークンをクリアする
    #
    # 【delete_all を使う理由】
    #   destroy_all はコールバックを実行するため遅い。
    #   delete_all は SQL DELETE を直接実行するためテストが高速になる。
    PasswordResetToken.where(user: @user).delete_all
  end

  # ============================================================
  # GET /password_resets/new （23番画面）
  # ============================================================

  test "GET /password_resets/new は正常に表示される" do
    get new_password_reset_path
    assert_response :success
  end

  test "ログイン済みユーザーは new にアクセスするとダッシュボードにリダイレクト" do
    log_in_as(@user)
    get new_password_reset_path
    assert_redirected_to dashboard_path
  end

  # ============================================================
  # POST /password_resets （メール送信）
  # ============================================================

  test "POST /password_resets は正しいメールアドレスでメールを送信する" do
    assert_enqueued_emails 1 do
      post password_resets_path, params: {
        password_reset: { email: @user.email }
      }
    end
    assert_redirected_to login_path
  end

  test "POST /password_resets は存在しないメールでも同じレスポンスを返す（列挙攻撃防止）" do
    # メールは送信されない
    assert_enqueued_emails 0 do
      post password_resets_path, params: {
        password_reset: { email: "notexist@example.com" }
      }
    end
    # しかし同じリダイレクト先（列挙攻撃防止）
    assert_redirected_to login_path
  end

  test "POST /password_resets は PasswordResetToken を作成する" do
    assert_difference "PasswordResetToken.count", 1 do
      post password_resets_path, params: {
        password_reset: { email: @user.email }
      }
    end
  end

  test "POST /password_resets に不正なパラメータが来ても500エラーにならない" do
    # params[:password_reset] 自体が存在しない不正リクエスト
    # params.dig を使っているため nil になり例外が発生しないことを確認
    assert_nothing_raised do
      post password_resets_path, params: {}
    end
    assert_redirected_to login_path
  end

  # ============================================================
  # GET /password_resets/:id/edit （26番画面）
  # ============================================================

  test "GET /password_resets/:id/edit は有効なトークンで表示される" do
    raw_token = PasswordResetToken.generate_token_for(@user)
    get edit_password_reset_path(raw_token)
    assert_response :success
  end

  test "GET /password_resets/:id/edit は無効なトークンで 404 を返す" do
    get edit_password_reset_path("invalid_token")
    assert_response :not_found
  end

  test "GET /password_resets/:id/edit は期限切れトークンで 404 を返す" do
    raw_token = PasswordResetToken.generate_token_for(@user)
    travel_to 25.hours.from_now do
      get edit_password_reset_path(raw_token)
      assert_response :not_found
    end
  end

  test "GET /password_resets/:id/edit は使用済みトークンで 404 を返す" do
    raw_token = PasswordResetToken.generate_token_for(@user)
    PasswordResetToken.find_by(user: @user).expire!
    get edit_password_reset_path(raw_token)
    assert_response :not_found
  end

  # ============================================================
  # PATCH /password_resets/:id （パスワード変更）
  # ============================================================

  test "PATCH /password_resets/:id は正しいパスワードでパスワードを変更できる" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_redirected_to login_path
    @user.reload
    assert @user.authenticate("newpassword123")
  end

  test "PATCH /password_resets/:id はパスワード変更後にトークンを使用済みにする" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    record = PasswordResetToken.find_by(user: @user)
    assert record.is_used
  end

  test "PATCH /password_resets/:id はパスワード変更後に使用済みURLへのアクセスを拒否する（再利用防止）" do
    # ============================================================
    # このテストが重要な理由:
    #   パスワード変更成功後、同じURLに再アクセスしても
    #   29番エラーページが表示されることを確認する。
    #   これによりトークンの使い捨てが正しく機能していることを保証する。
    # ============================================================
    raw_token = PasswordResetToken.generate_token_for(@user)

    # 1回目: パスワード変更成功
    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to login_path

    # 2回目: 同じURLへのアクセスは404（使用済みトークン）
    get edit_password_reset_path(raw_token)
    assert_response :not_found
  end

  test "PATCH /password_resets/:id は再発行時に旧トークンが無効になる" do
    # ============================================================
    # このテストが重要な理由:
    #   ユーザーが2回リセット申請した場合、
    #   古いメールのURLが使えないことを確認する。
    #   これにより「古いリセットメールの悪用」を防げていることを保証する。
    # ============================================================
    old_token = PasswordResetToken.generate_token_for(@user)
    # 2回目の申請（新しいトークンが発行される）
    _new_token = PasswordResetToken.generate_token_for(@user)

    # 古いトークンのURLにはアクセスできない
    get edit_password_reset_path(old_token)
    assert_response :not_found
  end

  test "PATCH /password_resets/:id はパスワード不一致でエラーを表示する" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "newpassword123",
        password_confirmation: "differentpassword"
      }
    }

    assert_response :unprocessable_entity
  end

  test "PATCH /password_resets/:id は短いパスワードでエラーを表示する" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "short",
        password_confirmation: "short"
      }
    }

    assert_response :unprocessable_entity
  end

  test "PATCH /password_resets/:id は無効なトークンで 404 を返す" do
    patch password_reset_path("invalid_token"), params: {
      password_reset: {
        password:              "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    assert_response :not_found
  end

  test "PATCH /password_resets/:id はパスワード変更失敗時にトークンが有効のまま残る" do
    # ============================================================
    # このテストが重要な理由:
    #   バリデーション失敗（短いパスワード等）のときに
    #   transaction がロールバックされ、
    #   トークンが無効化されていないことを確認する。
    #   ユーザーが再度正しいパスワードを入力できることを保証する。
    # ============================================================
    raw_token = PasswordResetToken.generate_token_for(@user)

    # バリデーション失敗するパスワードで送信
    patch password_reset_path(raw_token), params: {
      password_reset: {
        password:              "short",
        password_confirmation: "short"
      }
    }

    assert_response :unprocessable_entity

    # トークンがまだ有効であることを確認（ロールバック成功）
    record = PasswordResetToken.find_by(user: @user)
    assert_not record.is_used
    assert record.valid_token?
  end
end