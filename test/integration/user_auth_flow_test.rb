# test/integration/user_auth_flow_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# Issue #30: 統合テスト（主要フロー）
# 【テスト対象】ユーザー登録〜ログインのフロー
#
# 【統合テスト（IntegrationTest）とは？】
#   ActionDispatch::IntegrationTest を継承することで、
#   実際のHTTPリクエスト→レスポンスの流れをシミュレートできます。
#   単体テスト（モデルテスト）では確認できない
#   「コントローラー＋モデル＋ビュー＋ルーティング」の連携を検証します。
#
# 【このファイルがカバーする範囲】
#   - 新規ユーザー登録 → ダッシュボードへの自動遷移
#   - ログイン成功・失敗
#   - ログアウト
#   - 未ログイン時のアクセス制御
#
# 【既存テストとの棲み分け】
#   user_registration_test.rb → 登録フォームのバリデーション中心
#   user_login_test.rb        → ログインフォームの認証中心
#   ↑ この2ファイルで個別機能はカバー済み
#   ↓ このファイルは「登録→ログアウト→再ログイン」という
#     エンドツーエンドのフロー（一連の流れ）をテストします
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class UserAuthFlowTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回自動的に呼ばれる準備処理
  # ============================================================
  setup do
    # users(:one) → test/fixtures/users.yml の "one" キーのデータを取得
    # @user はこのクラス内の全テストメソッドで共有されます
    @user = users(:one)
  end

  # ============================================================
  # テスト1: 新規登録→ダッシュボード→ログアウト→再ログインの完全フロー
  # ============================================================
  # 【なぜこのフローを統合テストするのか？】
  # 個別テスト（user_registration_test.rb / user_login_test.rb）では
  # それぞれの機能を独立してテストしているが、
  # 「登録→ログアウト→再ログイン」という一連の流れは
  # セッション管理・リダイレクト先・flash メッセージが
  # 正しく連携しているかを確認するために必要です。
  test "新規登録→ダッシュボード表示→ログアウト→再ログインの完全フロー" do
    # ── Step 1: 新規ユーザー登録 ──────────────────────────────────
    # assert_difference("User.count", 1): このブロック実行後に User のレコードが1件増えることを確認
    # 増えない場合はテスト失敗（バリデーションエラーや保存失敗を検知できる）
    assert_difference("User.count", 1) do
      post users_path, params: {
        user: {
          name:                  "フローテストユーザー",
          email:                 "flow_test@example.com",
          password:              "password123",
          # password_confirmation は UsersController の user_params で permit されている
          # モデルの has_secure_password が「password と一致するか」をバリデーションします
          password_confirmation: "password123"
        }
      }
    end

    # UsersController#create は登録成功後に dashboard_path にリダイレクトします
    # assert_redirected_to: 指定パスへの 302 リダイレクトレスポンスかどうかを確認
    assert_redirected_to dashboard_path

    # follow_redirect!: リダイレクト先の URL に実際に GET リクエストを送る
    # これにより dashboard_path のレスポンスがセットされます
    follow_redirect!

    # ダッシュボードが表示されることを確認
    # assert_response :success → HTTP ステータス 200 OK であることを確認
    assert_response :success

    # assert_select "h1", text: /ダッシュボード/
    # → <h1> タグの中に「ダッシュボード」という文字列が含まれることを確認
    # /ダッシュボード/ は正規表現（完全一致ではなく部分一致）
    assert_select "h1", text: /ダッシュボード/

    # ── Step 2: ログアウト ────────────────────────────────────────
    # SessionsController#destroy を呼び出す
    # status: :see_other (303) は Rails 7 の Turbo 対応のためのリダイレクトコード
    delete logout_path

    # ログアウト後はランディングページ（root_path）にリダイレクトされます
    assert_redirected_to root_path

    # ── Step 3: ログアウト後のダッシュボードへのアクセス制御確認 ──
    # ログアウト済みなので、ダッシュボードにアクセスしようとしたら
    # require_login によってログインページにリダイレクトされるはず
    get dashboard_path
    assert_redirected_to login_path

    # ── Step 4: 再ログイン ────────────────────────────────────────
    # 同じメールアドレス・パスワードで再ログイン
    post login_path, params: {
      session: {
        email:    "flow_test@example.com",
        password: "password123"
      }
    }

    # SessionsController#create はログイン成功後に dashboard_path にリダイレクトします
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /ダッシュボード/
  end

  # ============================================================
  # テスト2: ログイン失敗→再試行→成功のフロー
  # ============================================================
  # 【なぜこのフローをテストするのか？】
  # 失敗後のセッション状態が正しくリセットされているか確認するため。
  # 失敗後にも正常にログインできることを保証します。
  test "ログイン失敗後に正しいパスワードで再試行すると成功すること" do
    # ── Step 1: 誤ったパスワードでログイン試行 ────────────────────
    post login_path, params: {
      session: {
        email:    @user.email,
        password: "wrong_password"  # 意図的に誤ったパスワードを送信
      }
    }

    # ログイン失敗時は SessionsController が render :new を返す
    # status: :unprocessable_entity → HTTP 422 が返ること
    assert_response :unprocessable_entity

    # ── Step 2: この時点では未ログイン状態のはず ──────────────────
    # ログイン失敗後にダッシュボードにアクセスしても弾かれることを確認
    get dashboard_path
    assert_redirected_to login_path

    # ── Step 3: 正しいパスワードで再試行 ─────────────────────────
    post login_path, params: {
      session: {
        email:    @user.email,
        password: "password"  # fixtures で BCrypt.create("password") と一致する正しいパスワード
      }
    }

    # 今度は成功してダッシュボードへリダイレクトされるはず
    assert_redirected_to dashboard_path
  end

  # ============================================================
  # テスト3: 未ログイン時の保護されたページへのアクセス制御
  # ============================================================
  # 【なぜこのテストが必要か？】
  # before_action :require_login が正しく機能しているかを確認するため。
  # HTTPリクエストを直接送ることで、ビューのボタン非活性化だけでなく
  # サーバー側でも適切にアクセス制御されていることを検証します。
  test "未ログイン時は保護されたページにアクセスできないこと" do
    # ダッシュボード: require_login で保護されている
    get dashboard_path
    assert_redirected_to login_path

    # 習慣一覧: require_login で保護されている
    get habits_path
    assert_redirected_to login_path

    # 習慣新規作成フォーム: require_login で保護されている
    get new_habit_path
    assert_redirected_to login_path

    # 週次振り返り一覧: require_login で保護されている
    get weekly_reflections_path
    assert_redirected_to login_path

    # 週次振り返り新規作成フォーム: require_login で保護されている
    get new_weekly_reflection_path
    assert_redirected_to login_path
  end
end
