# test/controllers/onboardings_controller_test.rb
#
# ==============================================================================
# OnboardingsController テスト（D-7 新規作成）
# ==============================================================================

require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストの前に実行される共通処理
  # ============================================================
  def setup
    # first_login_at が NULL のユーザー（オンボーディング未完了）を作成する
    # fixtures の users(:one) は first_login_at が設定されている可能性があるため
    # テスト用に独自に作成する
    @user = User.create!(
      name:     "テストユーザー",
      email:    "onboarding_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    # after_create コールバックで UserSetting も自動作成される（D-4 実装済み）

    # ログイン処理
    post login_path, params: { session: { email: @user.email, password: "password123" } }
  end

  def teardown
    # テスト用ユーザーのクリーンアップ（他のテストへの影響を防ぐ）
    @user.destroy if @user.persisted?
  end

  # ============================================================
  # step5 アクションのテスト（GET /onboarding/step5）
  # ============================================================

  # 【正常系】未完了ユーザーが step5 ページを表示できる
  test "step5: first_login_at が NULL のユーザーは step5 ページを表示できる" do
    assert_nil @user.first_login_at, "前提: first_login_at が NULL であること"

    get onboarding_step5_path

    assert_response :success
    # ページタイトルが含まれているか確認
    assert_select "h1", text: /目標を教えてください/
  end

  # 【異常系】完了済みユーザーはダッシュボードへリダイレクトされる
  test "step5: first_login_at が設定済みのユーザーはダッシュボードへリダイレクト" do
    # first_login_at を設定して「完了済み」状態にする
    @user.update_column(:first_login_at, Time.current)

    get onboarding_step5_path

    assert_redirected_to dashboard_path
  end

  # 【異常系】未ログインユーザーはログインページへリダイレクト
  test "step5: 未ログインユーザーはログインページへリダイレクト" do
    delete logout_path  # ログアウト
    get onboarding_step5_path

    assert_redirected_to login_path
  end

  # ============================================================
  # complete アクションのテスト（POST /onboarding/complete）
  # ============================================================

  # 【正常系】PMVV を入力して完了 → ダッシュボードへリダイレクト
  test "complete: PMVV を保存してダッシュボードへリダイレクトする" do
    assert_nil @user.first_login_at, "前提: first_login_at が NULL であること"

    post onboarding_complete_path, params: {
      user_purpose: {
        purpose: "家族と過ごす時間を大切にしたい",
        vision:  "毎朝6時に起きる",
        mission: "睡眠の質を改善する",
        value:   "家族との夕食は削らない",
        current_situation: "夜11時就寝、朝起きるのがつらい"
      }
    }

    assert_redirected_to dashboard_path

    # first_login_at が更新されているか確認
    @user.reload
    assert_not_nil @user.first_login_at,
                   "complete 後に first_login_at が設定されること"

    # UserPurpose が作成されているか確認
    assert_equal 1, @user.user_purposes.count,
                 "UserPurpose が1件作成されること"
  end

  # 【正常系】スキップ → ダッシュボードへリダイレクト + first_login_at 更新
  test "skip: PMVV を保存せずダッシュボードへリダイレクトする" do
    assert_nil @user.first_login_at, "前提: first_login_at が NULL であること"

    post onboarding_skip_path

    assert_redirected_to dashboard_path

    # first_login_at が更新されているか確認
    @user.reload
    assert_not_nil @user.first_login_at,
                   "skip 後に first_login_at が設定されること"

    # UserPurpose が作成されていないことを確認
    assert_equal 0, @user.user_purposes.count,
                 "skip 時は UserPurpose が作成されないこと"
  end

  # 【正常系】スキップ後に再度 step5 にアクセスしても戻れない
  test "skip: 完了後に step5 へアクセスするとダッシュボードへリダイレクト" do
    post onboarding_skip_path  # スキップして完了

    # 再度 step5 へアクセス
    get onboarding_step5_path

    assert_redirected_to dashboard_path,
                         "オンボーディング完了後は step5 に戻れないこと"
  end

  # 【正常系】complete 後に再度 step5 にアクセスしても戻れない
  test "complete: 完了後に step5 へアクセスするとダッシュボードへリダイレクト" do
    post onboarding_complete_path, params: {
      user_purpose: { purpose: "テスト" }
    }

    # 再度 step5 へアクセス
    get onboarding_step5_path

    assert_redirected_to dashboard_path,
                         "オンボーディング完了後は step5 に戻れないこと"
  end

  # 【正常系】require_login によるオンボーディングリダイレクト
  test "ダッシュボードへアクセスすると first_login_at NULL のユーザーは step5 へリダイレクト" do
    assert_nil @user.first_login_at, "前提: first_login_at が NULL であること"

    get dashboard_path

    assert_redirected_to onboarding_step5_path,
                         "初回ログインユーザーはダッシュボードにアクセスすると step5 へリダイレクト"
  end

  # 【異常系】完了済みユーザーの complete POST はダッシュボードへリダイレクト
  test "complete: 完了済みユーザーの POST はガードされダッシュボードへリダイレクト" do
    @user.update_column(:first_login_at, Time.current)

    post onboarding_complete_path, params: {
      user_purpose: { purpose: "テスト" }
    }

    assert_redirected_to dashboard_path
    # 完了済みのためユーザー目的は作成されない
    assert_equal 0, @user.user_purposes.count
  end
end