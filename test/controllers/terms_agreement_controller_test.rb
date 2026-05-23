# test/controllers/terms_agreement_controller_test.rb
#
# ==============================================================================
# TermsAgreementControllerTest（F-3 追加）
# ==============================================================================
#
# 【このテストの役割】
#   TermsAgreementController の show・agree アクションの基本動作を検証する。
#
# 【log_in_as と terms_agreed_at の関係について】
#   test_helper.rb の log_in_as は terms_agreed_at が nil のユーザーに対して
#   自動的に terms_agreed_at を設定してからログインする。
#   （他のテストが /terms_agreement にリダイレクトされないようにするため）
#
#   このテストでは「未同意状態」を作る必要があるため、
#   log_in_as の後に update_column(:terms_agreed_at, nil) で
#   明示的に未同意状態に戻す。
# ==============================================================================
require "test_helper"

class TermsAgreementControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # GET /terms_agreement（show アクション）
  # ============================================================

  test "未同意のログイン済みユーザーは同意ページを表示できる" do
    user = users(:one)
    log_in_as(user)

    # log_in_as が terms_agreed_at を自動設定するため、ログイン後に nil に戻す
    #
    # 【なぜ update_column を使うのか】
    #   update! だとバリデーションが再実行される。
    #   update_column は指定カラムのみバリデーションなしで直接更新するため安全。
    user.update_column(:terms_agreed_at, nil)

    get terms_agreement_path
    assert_response :success
  end

  test "未ログインユーザーはログインページへリダイレクトされる" do
    get terms_agreement_path

    # 未ログインなので require_login が働いてログインページへリダイレクトされる
    assert_redirected_to login_path(redirect_to: terms_agreement_path)
  end

  test "同意済みユーザーはダッシュボードへリダイレクトされる" do
    user = users(:one)
    # fixture の users(:one) は terms_agreed_at が設定済みのため同意済み
    log_in_as(user)

    get terms_agreement_path

    # ensure_needs_agreement がダッシュボードへリダイレクトする
    assert_redirected_to dashboard_path
  end

  # ============================================================
  # POST /terms_agreement（agree アクション）
  # ============================================================

  test "同意チェックありで terms_agreed_at が記録されダッシュボードへ遷移する" do
    # first_login_at が設定済みで onboarding 完了済みのユーザー
    user = users(:one)
    log_in_as(user)

    # ログイン後に未同意状態に戻す
    user.update_column(:terms_agreed_at, nil)

    assert_nil user.reload.terms_agreed_at

    post terms_agreement_agree_path, params: { terms_agreed: "1" }

    assert_not_nil user.reload.terms_agreed_at
    assert_redirected_to dashboard_path
  end

  test "初回ログインユーザーは同意後にオンボーディングへ遷移する" do
    # first_login_at が nil（オンボーディング未完了）のユーザーを作成する
    user = User.create!(
      name:             "初回ログインユーザー",
      email:            "first_login_terms_test@example.com",
      password:         "password",
      password_confirmation: "password",
      terms_agreed_at:  nil,   # 未同意
      first_login_at:   nil    # オンボーディング未完了
    )

    # log_in_as は terms_agreed_at が nil のとき自動設定するため、
    # ログイン後に手動で nil に戻す
    log_in_as(user)
    user.update_column(:terms_agreed_at, nil)
    user.update_column(:first_login_at,  nil)

    post terms_agreement_agree_path, params: { terms_agreed: "1" }

    # 同意後、first_login_at が nil なのでオンボーディングへ遷移する
    assert_redirected_to onboarding_step5_path

    user.destroy
  end

  test "同意チェックなしで送信すると同意ページが再表示される" do
    user = users(:one)
    log_in_as(user)

    # ログイン後に未同意状態に戻す
    user.update_column(:terms_agreed_at, nil)

    post terms_agreement_agree_path, params: { terms_agreed: "0" }

    # チェックなしなので agree アクションが show を再描画する
    assert_response :unprocessable_entity
  end

  test "未ログインユーザーの POST はログインページへリダイレクトされる" do
    post terms_agreement_agree_path, params: { terms_agreed: "1" }

    assert_redirected_to login_path(redirect_to: terms_agreement_path)
  end
end