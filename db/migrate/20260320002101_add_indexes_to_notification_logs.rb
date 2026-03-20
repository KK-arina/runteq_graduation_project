# db/migrate/YYYYMMDDHHMMSS_add_indexes_to_notification_logs.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# notification_logs テーブルに3種類のインデックスを追加する。
#
# 【なぜ追加が必要か？】
# 元のマイグレーションでは以下の2つのインデックスのみだった:
#   1. (user_id, created_at)      → ユーザー別の通知履歴取得用
#   2. (target_type, target_id)   → ポリモーフィック関連の検索用
#
# しかし管理・運用・分析の観点から、以下のクエリが頻繁に発生することが想定される:
#   - 「送信失敗した通知を一覧表示する」（status = 1）
#     → GoodJob でリトライ対象を特定するときに使う
#   - 「LINE 通知だけの履歴を取得する」（channel = 0）
#     → LINE API の上限管理・コスト分析に使う
#   - 「アラーム通知だけの件数を集計する」（notification_type = 0）
#     → ダッシュボードの統計・デバッグに使う
#
# インデックスなしでこれらのクエリを実行すると、
# テーブルを全件スキャン（Seq Scan）するため、レコード数が増えるほど遅くなる。
# ==============================================================================

class AddIndexesToNotificationLogs < ActiveRecord::Migration[7.2]
  # disable_ddl_transaction! を使う理由:
  # algorithm: :concurrently（並行インデックス作成）は PostgreSQL の仕様上、
  # トランザクション内では使用できない。
  # このディレクティブでマイグレーション全体をトランザクションなしで実行する。
  # これにより本番環境でインデックス作成中もテーブルへの書き込みがブロックされない。
  disable_ddl_transaction!

  def change
    # ─────────────────────────────────────────────────────────────────────────
    # status へのインデックス
    # ─────────────────────────────────────────────────────────────────────────
    # 送信失敗（status = 1）した通知をリトライするジョブが
    # WHERE status = 1 のクエリを頻繁に発行するため高速化が必要
    #
    # 部分インデックス（Partial Index）を使い、
    # status = 0（success）の大量の成功ログをインデックスから除外する
    # → インデックスのサイズを最小限に保てる（成功ログが大半を占めるため効果大）
    add_index :notification_logs,
              :status,
              where: 'status != 0',
              name: 'index_notification_logs_on_status_not_success',
              algorithm: :concurrently

    # ─────────────────────────────────────────────────────────────────────────
    # channel へのインデックス
    # ─────────────────────────────────────────────────────────────────────────
    # LINE 通知（channel = 0）の1日あたり送信件数チェックや
    # メール通知（channel = 1）のコスト分析クエリを高速化する
    # WHERE channel = ? の絞り込みに使用
    add_index :notification_logs,
              :channel,
              name: 'index_notification_logs_on_channel',
              algorithm: :concurrently

    # ─────────────────────────────────────────────────────────────────────────
    # notification_type へのインデックス
    # ─────────────────────────────────────────────────────────────────────────
    # 「アラーム通知（0）だけ」「週次レポート通知（1）だけ」などの
    # 種別ごとの集計・デバッグクエリを高速化する
    # 管理画面や Sentry のエラー追跡で使用頻度が高い
    add_index :notification_logs,
              :notification_type,
              name: 'index_notification_logs_on_notification_type',
              algorithm: :concurrently
  end
end