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
end