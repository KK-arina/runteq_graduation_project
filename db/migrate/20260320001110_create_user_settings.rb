# db/migrate/YYYYMMDDHHMMSS_create_user_settings.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# user_settings テーブルを新規作成する。
#
# 【このテーブルの役割】
# ユーザーごとの設定を一元管理するテーブル。
# 1ユーザーにつき1レコードのみ存在する（UNIQUE 制約で保証）。
#
# 【管理する設定の種類】
#   1. タイムゾーン設定       → アラーム時刻の計算に使用
#   2. 通知設定               → LINE 通知・メール通知の ON/OFF
#   3. お休みモード設定       → 旅行・病気時のストリーク維持
#   4. AI コスト制御          → 月間 AI 分析使用回数の管理
# ==============================================================================

class CreateUserSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :user_settings do |t|
      # ─────────────────────────────────────────────────────────────────────
      # user_id: どのユーザーの設定か（外部キー）
      # ─────────────────────────────────────────────────────────────────────
      # null: false → 必ずユーザーに紐づく
      # on_delete: :cascade → ユーザー削除時に設定も一緒に削除
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade }

      # ─────────────────────────────────────────────────────────────────────
      # タイムゾーン設定
      # ─────────────────────────────────────────────────────────────────────

      # time_zone: ユーザーのタイムゾーン
      # アラーム通知の時刻計算に使用する（例: 'Asia/Tokyo'）
      # string 型、デフォルトは日本標準時
      t.string :time_zone, default: 'Asia/Tokyo'

      # ─────────────────────────────────────────────────────────────────────
      # 通知設定
      # ─────────────────────────────────────────────────────────────────────

      # notification_enabled: 通知全体のマスタ ON/OFF
      # false にするとすべての通知が止まる（個別設定より優先する）
      t.boolean :notification_enabled, null: false, default: true

      # line_notification_enabled: LINE 通知の ON/OFF
      # LINE Messaging API を使ったプッシュ通知を有効にするか
      t.boolean :line_notification_enabled, null: false, default: false

      # email_notification_enabled: メール通知の ON/OFF
      # Resend を使ったメール通知を有効にするか
      t.boolean :email_notification_enabled, null: false, default: true

      # daily_notification_limit: 1日に送信できる通知の最大件数
      # LINE Messaging API の無料枠節約のために上限を設定する
      # integer 型、デフォルト5件
      t.integer :daily_notification_limit, null: false, default: 5

      # daily_notification_count: 当日に既に送信した通知件数
      # GoodJob の日次リセットジョブで毎日 0 に戻す
      t.integer :daily_notification_count, null: false, default: 0

      # notification_count_reset_at: 通知件数をリセットした日時
      # 「今日は既にリセット済みか」を確認するために使用する
      t.datetime :notification_count_reset_at

      # last_notification_sent_at: 最後に通知を送信した日時
      # 10秒以内の連続送信を防ぐスパム対策に使用する
      t.datetime :last_notification_sent_at

      # weekly_report_enabled: 週次レポートメールの送受信の ON/OFF
      # 毎週月曜日に送られる週次サマリーメールを受け取るか
      t.boolean :weekly_report_enabled, null: false, default: true

      # ─────────────────────────────────────────────────────────────────────
      # お休みモード設定
      # ─────────────────────────────────────────────────────────────────────

      # rest_mode_until: お休みモードの終了日時
      # NULL     = お休みモードではない（通常モード）
      # 日時あり = この日時までお休みモードが有効
      # GoodJob が毎日確認し、期限を過ぎたら自動的に解除する
      t.datetime :rest_mode_until

      # rest_mode_reason: お休みの理由（任意）
      # 例: '海外旅行' / '風邪で入院中'
      # string 型: NULL 許可（任意入力）
      t.string :rest_mode_reason

      # ─────────────────────────────────────────────────────────────────────
      # AI コスト制御
      # ─────────────────────────────────────────────────────────────────────

      # ai_analysis_count: 当月の AI 分析使用回数
      # 毎月1日に GoodJob の月次リセットジョブで 0 に戻す
      # integer 型、デフォルト 0
      t.integer :ai_analysis_count, null: false, default: 0

      # ai_analysis_monthly_limit: 月間の AI 分析使用回数の上限
      # デフォルト 10回（コスト管理のための制限）
      # 管理者が変更できるよう DB カラムとして保持する
      t.integer :ai_analysis_monthly_limit, null: false, default: 10

      # created_at・updated_at を自動で追加する
      t.timestamps
    end

    # ─────────────────────────────────────────────────────────────────────────
    # UNIQUE 制約: user_id を一意にする
    # ─────────────────────────────────────────────────────────────────────────
    # 1ユーザーにつき設定レコードは必ず1件のみ（重複を DB レベルで禁止）
    add_index :user_settings,
              :user_id,
              unique: true,
              name: 'index_user_settings_on_user_id_unique'
  end
end
