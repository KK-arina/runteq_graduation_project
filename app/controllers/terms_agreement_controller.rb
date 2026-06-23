# app/controllers/terms_agreement_controller.rb
#
# ==============================================================================
# TermsAgreementController（F-3 新規作成）
# ==============================================================================
#
# 【このコントローラーの役割】
#   OAuthでの初回ログイン時に利用規約・プライバシーポリシーへの同意を取得する。
#
# 【処理フロー】
#   1. OAuth 認証完了（Google / LINE）
#   2. OmniauthCallbacksController で terms_agreed? が false と判定
#   3. /terms_agreement へリダイレクト
#   4. ユーザーが同意チェックして「同意して続ける」を押す
#   5. agree アクションで terms_agreed_at を DB に記録
#   6. オンボーディング（first_login_at が nil）またはダッシュボードへ
#
# 【なぜ onboardings_controller.rb と分けるのか】
#   オンボーディング（PMVV入力）とは独立した法的同意フローとして
#   責任を明確に分離する。将来の規約改定対応もこのコントローラーのみ修正で済む。
# ==============================================================================

class TermsAgreementController < ApplicationController
  # require_login: 未ログインユーザーはログインページへリダイレクトする。
  #
  # 【なぜ必要なのか】
  #   OAuth ログイン後にセッションが確立されてから /terms_agreement に来るため、
  #   ログイン済みであることが前提。未ログインなら先にログインさせる。
  before_action :require_login

  # ensure_needs_agreement: すでに同意済みのユーザーをダッシュボードへ戻す。
  #
  # 【なぜ必要なのか】
  #   terms_agreed_at が設定済みのユーザーが /terms_agreement に
  #   直接アクセスしても意味がない。ダッシュボードへリダイレクトする。
  before_action :ensure_needs_agreement

  # ============================================================
  # show アクション（GET /terms_agreement）
  # ============================================================
  # 【役割】利用規約・プライバシーポリシー同意ページを表示する。
  def show
    # ビューを表示するだけ（インスタンス変数の設定は不要）
  end

  # ============================================================
  # agree アクション（POST /terms_agreement）
  # ============================================================
  # 【役割】同意チェックボックスの値を受け取り、terms_agreed_at を DB に記録する。
  def agree
    # params[:terms_agreed] の値（"1" または nil/""）を真偽値に変換する
    #
    # 【なぜ ActiveModel::Type::Boolean.new.cast を使うのか】
    #   フォームから来る "1"（文字列）を確実に true（bool）に変換するため。
    #   "1" → true / "" や "0" や nil → false のように変換できる。
    agreed = ActiveModel::Type::Boolean.new.cast(params[:terms_agreed])

    unless agreed
      # チェックなしで送信された場合はページを再表示してエラーを伝える
      flash.now[:alert] = t("terms_agreement.not_agreed")
      render :show, status: :unprocessable_entity
      return
    end

    # update_column を使って terms_agreed_at に現在時刻を直接書き込む
    #
    # 【なぜ update_column を使うのか】
    #   update! だとパスワードバリデーション等が再実行される可能性がある。
    #   update_column は指定カラムのみバリデーション・コールバックなしで
    #   直接 DB 更新するため、OAuth ユーザーでも安全に処理できる。
    #
    # 【update_column の注意点】
    #   updated_at が自動更新されないため、ここでは許容する。
    #   同意日時の記録目的であれば terms_agreed_at だけで十分。
    current_user.update_column(:terms_agreed_at, Time.current)

    # 同意記録後のリダイレクト先を決定する
    #
    # 【優先度】
    #   1. first_login_at が nil → オンボーディングへ（初回ログインユーザー）
    #   2. それ以外              → ダッシュボードへ
    if current_user.first_login_at.nil?
      redirect_to onboarding_step2_path,
                  notice: t("terms_agreement.agreed_and_onboarding")
    else
      redirect_to dashboard_path,
                  notice: t("terms_agreement.agreed")
    end
  end

  private

  # ensure_needs_agreement
  #
  # 【役割】
  #   すでに terms_agreed_at が設定済みのユーザーを
  #   ダッシュボードへリダイレクトする（同意ページへの再表示を防ぐ）。
  def ensure_needs_agreement
    redirect_to dashboard_path if current_user.terms_agreed?
  end
end