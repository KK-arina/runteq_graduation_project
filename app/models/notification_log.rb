# app/models/notification_log.rb
#
# ==============================================================================
# NotificationLog（通知ログ）モデル
# ==============================================================================
#
# 【このモデルの役割】
#   LINE通知・メール通知の送信履歴を記録するモデル。
#   notification_logs テーブルはすでに A-1 のマイグレーションで作成済み。
#   このファイルでは Rails がテーブルをどう扱うかを定義する。
#
# 【テーブルのカラム（schema.rb より）】
#   user_id           : 通知対象ユーザーの外部キー（必須）
#   notification_type : 通知の種類（0:alarm / 1:weekly_report / 2:ai_result / 3:crisis）
#   channel           : 送信チャネル（0:line / 1:email / 2:push）
#   target_type       : 通知対象モデル名（例: "Task"）polymorphic 用
#   target_id         : 通知対象レコードの id（例: タスクの id）
#   deep_link_url     : 通知タップ時の遷移先パス（例: "/tasks/1"）
#   status            : 送信結果（0:success / 1:failed / 2:skipped）
#   error_message     : エラー内容（失敗時のみ記録）
#   retry_count       : リトライ回数
#   metadata          : API レスポンスなどの補足情報（jsonb）
#   delivered_at      : 実際に配信された日時
#
# 【なぜ skip-migration オプションを使ったのか】
#   テーブルはすでに A-1 で作成済みのため、
#   新たにマイグレーションファイルを生成する必要がない。
#   skip-migration を指定することでモデルファイルだけを生成できる。
# ==============================================================================

class NotificationLog < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  # 【理由】
  #   notification_logs テーブルには user_id カラムがあり、
  #   1つの通知ログは必ず1人のユーザーに紐付く。
  #   schema.rb で add_foreign_key "notification_logs", "users", on_delete: :cascade
  #   と定義されているため、ユーザー削除時に通知ログも自動削除される。
  belongs_to :user

  # ============================================================
  # Enum 定義
  # ============================================================

  # enum :notification_type（通知の種類）
  # 【各値の意味】
  #   alarm         : タスクのアラーム通知（C-5 で実装）
  #   weekly_report : 週次レポートの通知（G-2 で実装予定）
  #   ai_result     : AI分析完了の通知（D-3 で実装予定）
  #   crisis        : 危機介入の通知（D-5 で実装予定）
  #
  # 【なぜ整数で保存するのか】
  # DB に文字列ではなく整数（0/1/2/3）で保存することで、
  # インデックスが効きやすくなりクエリが高速になる。
  # Rails の enum 機能が自動的に整数 ↔ シンボル の変換をしてくれるため、
  # コードでは notification_log.alarm? のように使える。
  enum :notification_type, {
    alarm:         0,
    weekly_report: 1,
    ai_result:     2,
    crisis:        3
  }

  # enum :channel（送信チャネル）
  # 【各値の意味】
  #   line  : LINE Messaging API 経由で送信
  #   email : メール（Resend）経由で送信
  #   push  : Web Push 通知経由（将来実装予定）
  enum :channel, {
    line:  0,
    email: 1,
    push:  2
  }

  # enum :status（送信ステータス）
  # 【各値の意味】
  #   success : 正常に送信できた
  #   failed  : 送信に失敗した（error_message に詳細を記録）
  #   skipped : 上限超過・設定無効などの理由でスキップした
  enum :status, {
    success: 0,
    failed:  1,
    skipped: 2
  }

  # ============================================================
  # バリデーション
  # ============================================================

  # user は必須
  # notification_type は必須（enum に含まれる値のみ許可）
  # channel は必須（enum に含まれる値のみ許可）
  validates :notification_type, presence: true
  validates :channel,           presence: true

  # ============================================================
  # スコープ
  # ============================================================

  # scope :recent
  # 【役割】
  #   作成日時の新しい順で通知ログを取得する。
  #   管理画面やデバッグ時に使いやすくするための便利スコープ。
  scope :recent, -> { order(created_at: :desc) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # self.record_success
  # 【役割】
  #   通知送信成功時に NotificationLog レコードを作成する便利メソッド。
  #   引数をまとめて渡すことでコントローラー・ジョブ側のコードをシンプルにする。
  #
  # 【引数の説明】
  #   user:              通知を送ったユーザーのインスタンス
  #   notification_type: 通知の種類（:alarm など）
  #   channel:           送信チャネル（:line / :email）
  #   target:            通知対象のレコード（Taskインスタンスなど）
  #   deep_link_url:     タップ時の遷移先パス（例: "/tasks/1"）
  #   metadata:          APIレスポンスなどの補足情報（省略可）
  def self.record_success(user:, notification_type:, channel:, target:, deep_link_url:, metadata: nil)
    create!(
      user:              user,
      notification_type: notification_type,
      channel:           channel,
      # target_type / target_id は polymorphic 関連のため
      # target オブジェクトのクラス名と id を個別にセットする
      target_type:   target.class.name,
      target_id:     target.id,
      deep_link_url: deep_link_url,
      status:        :success,
      delivered_at:  Time.current,
      metadata:      metadata
    )
  end

  # self.record_failure
  # 【役割】
  #   通知送信失敗時に NotificationLog レコードを作成する便利メソッド。
  #   error_message に失敗理由を記録することでデバッグを容易にする。
  def self.record_failure(user:, notification_type:, channel:, target:, deep_link_url:, error_message:)
    create!(
      user:              user,
      notification_type: notification_type,
      channel:           channel,
      target_type:   target.class.name,
      target_id:     target.id,
      deep_link_url: deep_link_url,
      status:        :failed,
      error_message: error_message
    )
  end

  # self.record_skip
  # 【役割】
  #   上限超過・通知無効などの理由でスキップした場合に記録する便利メソッド。
  #   「なぜ通知しなかったか」を追跡できるようにする。
  def self.record_skip(user:, notification_type:, channel:, target:, deep_link_url:, reason:)
    create!(
      user:              user,
      notification_type: notification_type,
      channel:           channel,
      target_type:   target.class.name,
      target_id:     target.id,
      deep_link_url: deep_link_url,
      status:        :skipped,
      # スキップ理由を error_message カラムに記録する
      # （専用カラムはないため error_message を流用する）
      error_message: reason
    )
  end
end