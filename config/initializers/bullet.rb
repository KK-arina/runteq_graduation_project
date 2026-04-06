# config/initializers/bullet.rb
#
# ==============================================================================
# 【このファイルの役割】
# Bullet gem の設定ファイルです。
# N+1クエリ（不必要なSQLが大量発行される問題）を自動で検出します。
#
# 【N+1クエリとは】
# 10件の習慣を表示するとき、各習慣の記録を1件ずつDBから取得すると
# 「習慣一覧1回 + 各習慣の記録10回」= 11回のSQLが発行されます。
# includes を使えば「2回」で済みます。この差が「N+1問題」です。
# ==============================================================================
if Rails.env.development?
  Bullet.enable = true
  # 【Bullet.enable = true】
  # Bullet全体のON/OFFスイッチ。
  # false にするとすべての検出機能が無効になる。
  Bullet.alert = true
  # 【Bullet.alert = true】
  # N+1が検出されたとき、ブラウザのJavaScriptポップアップで警告表示する。
  # 開発中に画面を見ていればすぐ気づける。
  Bullet.rails_logger = true
  # 【Bullet.rails_logger = true】
  # N+1が検出されたとき、Railsのログ（log/development.log）に記録する。
  # docker compose logs -f web でリアルタイム確認できる。
  Bullet.add_footer = true
  # 【Bullet.add_footer = true】
  # ブラウザのページ下部にN+1の警告をフッターとして表示する。
  # アラートが邪魔な場合の代替手段としても使える。
  Bullet.unused_eager_loading_enable = true
  # 【Bullet.unused_eager_loading_enable = true】
  # ★ レビュー指摘①：追加推奨
  # 「includes で先読みしたのに実際は使わなかった」問題も検出する。
  # N+1の逆パターン（過剰なEager Loading）も防げる。
  #
  # 【具体例】
  # @habits = Habit.includes(:habit_records)
  # ビューで habit_records を一度も使わなかった → 無駄なSQLが1本走った
  # → Bullet が警告してくれる

  # ── C-1 追加: Bullet 誤検知の抑制 ──────────────────────────────────────
  #
  # 【対象】
  #   Habit モデルの :habit_excluded_days アソシエーション
  #
  # 【誤検知が発生する理由】
  #   DashboardsController#index で includes(:habit_excluded_days) を設定しているが、
  #   build_habit_stats 内で habits.select(&:check_type?) によって Ruby レベルで
  #   チェック型習慣のみに絞り込んでから effective_weekly_target を呼ぶため、
  #   Bullet が「数値型習慣では habit_excluded_days を使っていない」と誤判定する。
  #
  #   実際にはチェック型習慣では effective_weekly_target → habit_excluded_days.size が
  #   必ず参照されるため、includes は N+1 防止として正しく機能している。
  #
  # 【add_safelist とは】
  #   Bullet のセーフリストに登録することで、指定した組み合わせの警告を抑制する。
  #   type: :unused_eager_loading で「不要な eager loading」の誤検知を対象にする。
  #   class: でモデル名、association: で関連名を指定する。
  Bullet.add_safelist(type: :unused_eager_loading, class_name: "Habit", association: :habit_excluded_days)
  # ────────────────────────────────────────────────────────────────────────
end