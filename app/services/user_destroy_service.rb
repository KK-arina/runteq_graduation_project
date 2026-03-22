# app/services/user_destroy_service.rb
#
# ============================================================
# 【このファイルの役割】
# ユーザー退会フローのビジネスロジックを集約するサービスクラス。
#
# 【Issue #A-7 最終修正版】
# rescue をサービスクラス側に移動。
# ============================================================

class UserDestroyService
  def initialize(user:)
    @user = user
  end

  def call
    ApplicationRecord.with_transaction do
      anonymized_email = "deleted_#{@user.id}@deleted.invalid"

      # update_columns を使う理由:
      # メールを "deleted_xxx@deleted.invalid" という通常無効な形式に変えるため
      # before_save の downcase_email バリデーションをバイパスする必要がある。
      # これは意図的な設計。
      @user.update_columns(
        deleted_at:      Time.current,
        name:            "退会済みユーザー",
        email:           anonymized_email,
        password_digest: "",
        line_user_id:    nil,
        provider:        "deleted",
        uid:             nil
      )

      # パスワードリセットトークンを削除する
      PasswordResetToken.where(user_id: @user.id).delete_all

      # ユーザー設定の通知フラグを全て無効化する
      UserSetting.where(user_id: @user.id).update_all(
        notification_enabled:       false,
        line_notification_enabled:  false,
        email_notification_enabled: false
      )
    end

    { success: true, error: nil }

  rescue StandardError => e
    Rails.logger.error "[UserDestroyService] StandardError: #{e.message}"
    Rails.logger.error e.backtrace&.first(10)&.join("\n")
    { success: false, error: "退会処理中にエラーが発生しました。" }
  end
end