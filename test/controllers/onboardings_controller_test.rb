# test/controllers/onboardings_controller_test.rb
#
# ==============================================================================
# OnboardingsController テスト（E-1修正: UserPurpose 5フィールド必須化対応）
# ==============================================================================
# 【E-1修正での変更内容】
#   UserPurpose の5フィールドが presence: true になったため、
#   以下の2つのテストを修正する:
#
#   ① "complete: 完了後に step5 へアクセスするとダッシュボードへリダイレクト"
#      変更前: purpose: "テスト" のみ送信
#      変更後: 5フィールドすべてを送信
#      【なぜ修正が必要か】
#        purpose のみだと mission/vision/value/current_situation のバリデーションエラーで
#        complete アクションの save が失敗する。
#        save が失敗すると complete_onboarding! が呼ばれず first_login_at が更新されない。
#        first_login_at が nil のまま再度 step5 へアクセスしても
#        ensure_needs_onboarding が通過してしまい、ダッシュボードへリダイレクトされない。
#
#   ② "complete: 完了済みユーザーの POST はガードされダッシュボードへリダイレクト"
#      変更前: purpose: "テスト" のみ送信
#      変更後: このテストは first_login_at が設定済みのユーザーへのリクエストのため
#              ensure_needs_onboarding でリダイレクトされる（バリデーションは走らない）。
#              変更不要だが、コメントで意図を明記する。
# ==============================================================================

require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # first_login_at が NULL のユーザー（オンボーディング未完了）を作成する
    @user = User.create!(
      name:     "テストユーザー",
      email:    "onboarding_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )

    post login_path, params: { session: { email: @user.email, password: "password123" } }
  end

  def teardown
    @user.destroy if @user.persisted?
  end

  # ── 共通フォームパラメータ ────────────────────────────────────────────────
  #
  # 【E-1修正: このヘルパーを追加した理由】
  #   UserPurpose の5フィールドが必須化されたため、
  #   complete アクションへの POST では5フィールドすべてを送信する必要がある。
  #   各テストで重複するパラメータをまとめ、変更が1か所で済むようにする。
  def valid_purpose_params(overrides = {})
    {
      purpose:           "家族と過ごす時間を大切にしたい",   # 必須
      mission:           "睡眠の質を改善する",              # 必須 E-1追加
      vision:            "毎朝6時に起きる",                  # 必須
      value:             "家族との夕食は削らない",            # 必須 E-1追加
      current_situation: "夜11時就寝、朝起きるのがつらい"    # 必須 E-1追加
    }.merge(overrides)
  end
  # ────────────────────────────────────────────────────────────────────────────

  # ============================================================
  # step5 アクションのテスト
  # ============================================================

  test "step5: first_login_at が NULL のユーザーは step5 ページを表示できる" do
    assert_nil @user.first_login_at

    get onboarding_step5_path

    assert_response :success
    assert_select "h1", text: /目標を教えてください/
  end

  test "step5: first_login_at が設定済みのユーザーはダッシュボードへリダイレクト" do
    @user.update_column(:first_login_at, Time.current)

    get onboarding_step5_path

    assert_redirected_to dashboard_path
  end

  test "step5: 未ログインユーザーはログインページへリダイレクト" do
    delete logout_path
    get onboarding_step5_path

    assert_redirected_to %r{/login}
  end

  # ============================================================
  # complete アクションのテスト
  # ============================================================

  test "complete: PMVV を保存してダッシュボードへリダイレクトする" do
    assert_nil @user.first_login_at

    post onboarding_complete_path, params: {
      user_purpose: valid_purpose_params
    }

    assert_redirected_to dashboard_path

    @user.reload
    assert_not_nil @user.first_login_at
    assert_equal 1, @user.user_purposes.count
  end

  test "skip: PMVV を保存せずダッシュボードへリダイレクトする" do
    assert_nil @user.first_login_at

    post onboarding_skip_path

    assert_redirected_to dashboard_path

    @user.reload
    assert_not_nil @user.first_login_at
    assert_equal 0, @user.user_purposes.count
  end

  test "skip: 完了後に step5 へアクセスするとダッシュボードへリダイレクト" do
    post onboarding_skip_path

    get onboarding_step5_path

    assert_redirected_to dashboard_path,
                         "オンボーディング完了後は step5 に戻れないこと"
  end

  # ── E-1修正: 5フィールドすべてを送信するように変更 ────────────────────────
  #
  # 【変更前】
  #   post onboarding_complete_path, params: {
  #     user_purpose: { purpose: "テスト" }
  #   }
  #
  # 【変更後】valid_purpose_params を使用して5フィールドすべてを送信
  #
  # 【なぜ変更が必要か】
  #   purpose のみ送信すると mission/vision/value/current_situation のバリデーションエラーで
  #   UserPurpose の save が失敗する。
  #   save が失敗すると complete_onboarding! が呼ばれず first_login_at が nil のまま。
  #   first_login_at が nil だと ensure_needs_onboarding を通過してしまい、
  #   再アクセス時にダッシュボードへリダイレクトされず、テストが失敗する。
  test "complete: 完了後に step5 へアクセスするとダッシュボードへリダイレクト" do
    post onboarding_complete_path, params: {
      user_purpose: valid_purpose_params
    }

    get onboarding_step5_path

    assert_redirected_to dashboard_path,
                         "オンボーディング完了後は step5 に戻れないこと"
  end
  # ────────────────────────────────────────────────────────────────────────────

  test "ダッシュボードへアクセスすると first_login_at NULL のユーザーは step5 へリダイレクト" do
    assert_nil @user.first_login_at

    get dashboard_path

    assert_redirected_to onboarding_step5_path
  end

  # ── このテストは変更不要 ──────────────────────────────────────────────────
  #
  # 【なぜ変更不要か】
  #   @user.update_column で first_login_at を設定済みにしているため、
  #   onboardings_controller の ensure_needs_onboarding が先に動き
  #   dashboard_path へリダイレクトされる。
  #   UserPurpose のバリデーションは走らないため、purpose だけでも問題ない。
  test "complete: 完了済みユーザーの POST はガードされダッシュボードへリダイレクト" do
    @user.update_column(:first_login_at, Time.current)

    post onboarding_complete_path, params: {
      user_purpose: { purpose: "テスト" }
    }

    assert_redirected_to dashboard_path
    assert_equal 0, @user.user_purposes.count
  end
  # ────────────────────────────────────────────────────────────────────────────
end
