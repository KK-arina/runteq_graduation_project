class ApplicationJob < ActiveJob::Base
  # ============================================================
  # Issue #A-3: GoodJob 共通設定
  # ============================================================
  #
  # 【リトライ設定】
  # 一時的なエラー（DB接続失敗・API タイムアウト等）は自動リトライする。
  # wait: :exponentially_longer → 5秒・25秒・125秒と指数的に待機間隔を延ばす。
  # これにより短時間のリトライ集中を防ぎ、DB や外部API への負荷を抑える。
  # attempts: 3 → 最大3回試行後に Discarded（破棄）状態になる。
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # 【即時破棄設定】
  # 対象レコードが存在しないケースはリトライしても無意味なため即座に破棄する。
  # 例: ユーザーが退会後にそのユーザーへの通知ジョブが実行された場合
  discard_on ActiveRecord::RecordNotFound
end