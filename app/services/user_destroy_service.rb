# app/services/user_destroy_service.rb
#
# ==============================================================================
# UserDestroyService: ユーザー退会処理サービスクラス（F-6 確定版・B案統計保持）
# ==============================================================================
#
# 【削除ポリシー（確定版）】
#
#   ■ 即時匿名化（上書き）
#     - name          → "退会済みユーザー"
#     - email         → "deleted_{id}@deleted.invalid"
#                       ※ id を使うことで一意性を保ちつつ元メールが解放される
#     - password_digest → BCrypt でハッシュ化したランダム文字列
#                         ※ nil だと null: false 制約で落ちる場合がある
#                         ※ 空文字だと has_secure_password と相性が悪い
#                         ※ 既知パターンにならないよう SecureRandom.hex(32) を使用
#     - line_user_id  → nil
#     - provider      → "deleted"
#     - uid           → nil
#     - updated_at    → Time.current（update_columns は自動更新しないため明示）
#
#   ■ 論理削除
#     - deleted_at    → Time.current
#
#   ■ 統計用に匿名化して保持（物理削除しない）
#     - habits / tasks / weekly_reflections / user_purposes / ai_analyses
#
#   ■ セキュリティリスクがあるため物理削除
#     - PasswordResetToken: 退会後にパスワードリセットURLを悪用されると危険
#     - PushSubscription:   退会後に通知が届いてしまうと危険
#
# 【Issue #A-7 との連携】
#   ApplicationRecord.with_transaction を使いトランザクション管理する。
#   rescue はサービスクラス側でのみ行い、with_transaction 内には書かない。
# ==============================================================================

class UserDestroyService
  # initialize: サービスクラスの初期化メソッド
  #
  # keyword argument（user:）を使う理由:
  #   呼び出し側で UserDestroyService.new(user: current_user) と書けるため、
  #   何を渡しているのかが明確になる（可読性向上）。
  def initialize(user:)
    @user = user
  end

  # call: 退会処理を実行するメインメソッド
  #
  # 【戻り値】
  #   成功時: { success: true,  error: nil }
  #   失敗時: { success: false, error: "エラーメッセージ" }
  def call
    ApplicationRecord.with_transaction do
      # ─── ① ユーザーの個人情報を匿名化する ─────────────────────────────────
      #
      # anonymized_email の形式:
      #   "deleted_{user.id}@deleted.invalid"
      #   ・user.id を使うことで複数ユーザーが退会しても一意性が保たれる
      #   ・元のメールアドレスは解放されるので同じアドレスで再登録可能になる
      #   ・".invalid" ドメインは RFC 2606 で「実在しないドメイン」として予約済み
      #
      # 【SecureRandom.uuid を使わない理由】
      #   uuid を使うと元のメールアドレスが解放されることは同じだが、
      #   「どのユーザーが退会したか」をシステム内部で追跡する手段がなくなる。
      #   user.id を使う方が運用上の追跡可能性が高い。
      anonymized_email = "deleted_#{@user.id}@deleted.invalid"

      # ─── 安全なランダムパスワードハッシュを生成する ─────────────────────────
      #
      # BCrypt::Password.create(SecureRandom.hex(32)) を使う理由:
      #   ① nil にしない理由: DB の password_digest に null: false 制約がある場合に落ちる
      #   ② "" にしない理由: has_secure_password が空文字に対して予期しない動作をする
      #   ③ 固定文字列にしない理由: ブルートフォースで突破されるリスクがある
      #   ④ SecureRandom.hex(32): 256bit のランダム文字列で事実上解読不可能
      #   ⑤ BCrypt.create: Rails の authenticate が必ず失敗する形式で保存する
      random_password_hash = BCrypt::Password.create(SecureRandom.hex(32))

      # update_columns を使う理由:
      #   バリデーションとコールバックをスキップして直接DBを更新する。
      #   before_save :downcase_email など不要なコールバックを走らせない。
      #   updated_at を明示する理由: update_columns は Rails が自動更新しない。
      @user.update_columns(
        deleted_at:      Time.current,
        name:            "退会済みユーザー",
        email:           anonymized_email,
        password_digest: random_password_hash,
        line_user_id:    nil,
        provider:        "deleted",
        uid:             nil,
        updated_at:      Time.current
      )

      # ─── ② セキュリティリスクがあるデータを物理削除する ──────────────────────
      #
      # PasswordResetToken: 退会後にパスワードリセットURLを悪用されると危険
      PasswordResetToken.where(user_id: @user.id).delete_all

      # push_subscriptions: モデルファイルが未作成のためSanitizeしたSQLで直接削除する
      #
      # 【なぜ ActiveRecord::Base.sanitize_sql を使うのか】
      #   PushSubscription モデルクラスが存在しないため
      #   ActiveRecord モデル経由での削除ができない。
      #   sanitize_sql_for_conditions を使うことで
      #   プレースホルダー形式でSQLインジェクションを防ぎながら直接削除できる。
      sql = ActiveRecord::Base.sanitize_sql_array(
        [ "DELETE FROM push_subscriptions WHERE user_id = ?", @user.id ]
      )
      ActiveRecord::Base.connection.execute(sql)
    end

    # トランザクション成功時の戻り値
    { success: true, error: nil }

  rescue ActiveRecord::StatementInvalid => e
    # SQL 文が不正なとき（外部キー制約違反など）に発生する例外
    Rails.logger.error "[UserDestroyService] StatementInvalid: #{e.message}"
    { success: false, error: "退会処理中にデータベースエラーが発生しました。" }

  rescue StandardError => e
    # 上記以外の予期しないエラー全般を捕捉する
    Rails.logger.error "[UserDestroyService] StandardError: #{e.message}"
    Rails.logger.error e.backtrace&.first(10)&.join("\n")
    { success: false, error: "退会処理中に予期しないエラーが発生しました。" }
  end
end