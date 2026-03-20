# db/migrate/YYYYMMDDHHMMSS_create_notification_logs.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# notification_logs テーブルを新規作成する。
#
# 【このテーブルの役割】
# LINE 通知・メール通知の送信履歴を記録するログテーブル。
# いつ・誰に・どんな通知を・どのチャネルで・成功/失敗したかを追跡できる。
#
# 【notification_type（通知種別）の値】
#   0: alarm          → タスクのアラーム通知
#   1: weekly_report  → 週次レポート通知
#   2: ai_result      → AI 分析完了通知
#   3: crisis         → 危機介入後の通知
#
# 【channel（通知チャネル）の値】
#   0: line   → LINE Messaging API
#   1: email  → メール（Resend）
#   2: push   → Web Push（将来実装予定）
#
# 【status（送信結果）の値】
#   0: success  → 送信成功
#   1: failed   → 送信失敗
#   2: skipped  → スキップ（1日の上限超過など）
#
# 【deep_link_url とは？】
# 通知メッセージに含める URL。
# LINE の通知をタップしたとき、このURLを開くことで
# ログインページを経由してアプリ内の特定画面に直接遷移できる。
# 例: '/weekly_reflections/new' → 振り返り入力ページに遷移
# ==============================================================================

class CreateNotificationLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :notification_logs do |t|
      # ─────────────────────────────────────────────────────────────────────
      # user_id: 通知を送ったユーザー（外部キー）
      # ─────────────────────────────────────────────────────────────────────
      # null: false → 必ずユーザーに紐づく
      # on_delete: :cascade → ユーザー削除時にログも一緒に削除
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade }

      # ─────────────────────────────────────────────────────────────────────
      # notification_type: 通知の種別
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理
      # null: false → 必須項目
      t.integer :notification_type, null: false

      # ─────────────────────────────────────────────────────────────────────
      # channel: 通知チャネル（LINE / メール / Push）
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理
      # null: false → 必須項目
      t.integer :channel, null: false

      # ─────────────────────────────────────────────────────────────────────
      # target_type / target_id: 通知の対象オブジェクト（ポリモーフィック）
      # ─────────────────────────────────────────────────────────────────────
      # 通知がどのオブジェクトに関連するかを保存する「ポリモーフィック関連」の設定
      # target_type: オブジェクトのクラス名（例: 'Task' / 'WeeklyReflection'）
      # target_id:   オブジェクトのIDの値
      # 例: Task のアラーム通知 → target_type='Task', target_id=123
      # NULL 許可: 特定のオブジェクトに紐づかない通知もある（週次レポートなど）
      t.string :target_type
      t.bigint :target_id

      # ─────────────────────────────────────────────────────────────────────
      # deep_link_url: 通知タップ時の遷移先 URL パス
      # ─────────────────────────────────────────────────────────────────────
      # LINE の通知メッセージにこの URL を埋め込む。
      # ユーザーが通知をタップすると、ブラウザでこの URL を開く。
      # 未ログインの場合は /login?redirect_to={deep_link_url} を経由して
      # ログイン後に指定の画面へ自動遷移する。
      #
      # 例:
      #   '/weekly_reflections/new' → 振り返り入力ページ
      #   '/tasks/123'              → タスク一覧ページ
      #   '/user_purposes/456'      → PMVV詳細・AI分析結果ページ
      #
      # string 型: NULL 許可（遷移先なしの通知の場合は NULL）
      t.string :deep_link_url

      # ─────────────────────────────────────────────────────────────────────
      # status: 送信結果
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: 0=success / 1=failed / 2=skipped
      # null: false → 必須項目
      t.integer :status, null: false, default: 0

      # ─────────────────────────────────────────────────────────────────────
      # error_message: 失敗時のエラー内容
      # ─────────────────────────────────────────────────────────────────────
      # status が failed（1）のときにエラーの詳細を保存する
      # Sentry でエラーを追跡するための補助情報としても使用
      # text 型: NULL 許可（成功時は NULL）
      t.text :error_message

      # ─────────────────────────────────────────────────────────────────────
      # retry_count: リトライ回数
      # ─────────────────────────────────────────────────────────────────────
      # 最初の送信を 0 とし、リトライするたびに 1 ずつ増加する
      # 最大リトライ回数に達したら status を failed に更新する
      t.integer :retry_count, null: false, default: 0

      # ─────────────────────────────────────────────────────────────────────
      # metadata: API レスポンスの詳細情報（JSON 形式）
      # ─────────────────────────────────────────────────────────────────────
      # LINE API や Resend API からのレスポンス内容を保存するデバッグ用フィールド
      # jsonb 型: NULL 許可
      t.jsonb :metadata

      # ─────────────────────────────────────────────────────────────────────
      # delivered_at: 実際に届いた日時（確認できた場合）
      # ─────────────────────────────────────────────────────────────────────
      # webhook で「既読確認」などが取れた場合に保存する
      # datetime 型: NULL 許可
      t.datetime :delivered_at

      # created_at・updated_at を自動で追加する
      t.timestamps
    end

    # ─────────────────────────────────────────────────────────────────────────
    # INDEX の追加（2種類）
    # ─────────────────────────────────────────────────────────────────────────

    # INDEX 1: (user_id, created_at)
    # 「このユーザーの通知履歴を新しい順に取得する」クエリを高速化
    # 設定ページの「通知履歴」表示や、1日の送信回数チェックに使用
    add_index :notification_logs,
              [ :user_id, :created_at ],
              name: 'index_notification_logs_on_user_id_and_created_at'

    # INDEX 2: (target_type, target_id)
    # 「このタスクに関連する通知履歴を取得する」クエリを高速化
    # ポリモーフィック関連の検索（WHERE target_type='Task' AND target_id=123）に使用
    add_index :notification_logs,
              [ :target_type, :target_id ],
              name: 'index_notification_logs_on_target_type_and_target_id'
  end
end
