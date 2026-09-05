class ApplicationJob < ActiveJob::Base
  # ============================================================
  # Issue #A-3 / #I-3: GoodJob 共通設定（全ジョブ共通のリトライ／破棄ポリシー）
  # ============================================================
  #
  # 【リトライ設定】
  #   一時的なエラー（DB接続失敗・API タイムアウト等）は自動でリトライする。
  #
  # 【wait: :polynomially_longer について（#I-3 で修正）】
  #   以前は wait: :exponentially_longer を指定していたが、この値は
  #   Rails 7.1 で非推奨になり、Rails 7.2 で「削除」された
  #   （公式リリースノート: "Remove deprecated :exponentially_longer value
  #     for the :wait in retry_on."）。
  #   本番は Rails 8.1.3 のため、この値は既に存在せず、実際にリトライしようと
  #   した瞬間に
  #     RuntimeError: Couldn't determine a delay based on :exponentially_longer
  #   が発生してジョブが二次的にクラッシュする（本番の Sentry で検知）。
  #   Rails 7.1 以降の正式名称である :polynomially_longer に置き換える。
  #   → もともと指数ではなく多項式バックオフ（executions**4 ベース）で、
  #     名称が実態に合わせて変わっただけ。待機が段階的に延びる挙動は同じ。
  #
  # 【attempts: 3 の意味】
  #   最大3回試行しても失敗する場合は Discarded（破棄）状態にする。
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # 【即時破棄設定】
  #   対象レコードが存在しないケースはリトライしても無意味なため即座に破棄する。
  #   例: ユーザーが退会後に、そのユーザー宛の通知ジョブが実行された場合。
  discard_on ActiveRecord::RecordNotFound

  # ※ 一意制約違反（ActiveRecord::RecordNotUnique）はここ（親クラス）では扱わない。
  #   全ジョブで一律に discard すると、他のジョブで起きた「本来調査すべき重複」まで
  #   黙って握りつぶし、Sentry で本物の障害を見逃すおそれがあるため。
  #   AI分析ジョブの並行実行による重複は、各ジョブ側で個別に安全に処理する
  #   （weekly_reflection_analysis_job.rb / purpose_analysis_job.rb を参照）。
end
