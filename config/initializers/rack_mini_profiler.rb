# config/initializers/rack_mini_profiler.rb
#
# ==============================================================================
# 【このファイルの役割】
# rack-mini-profiler gem の設定ファイルです。
# ブラウザの左上に「このページで何回SQLが実行されたか・何ミリ秒かかったか」を
# リアルタイムで表示します。
#
# 【gem名と require 名の違いについて】
# Ruby の require はファイルシステム上のファイル名を指定する。
# Rubyのファイル名にハイフンは使えないため、
# gem名がハイフンの場合でも require 名はアンダースコアになる。
#
#   gem名（Gemfile に書く名前）: rack-mini-profiler
#   require名（require に書く名前）: rack_mini_profiler（アンダースコア）
#
# 【rescue LoadError を入れている理由】
# Docker環境では bundle install の完了前に initializer が読み込まれる
# タイミングの問題が起きることがある。
# rescue LoadError を入れることで gem が未インストールの状態でも
# アプリが起動できなくなることを防ぐ。
# ==============================================================================

if Rails.env.development?
  begin
    # ✅ 正しい require 名はアンダースコア（ハイフンではない）
    # gem名: rack-mini-profiler
    # require名: rack_mini_profiler
    # Gemfile で require: false を指定しているため手動 require が必要
    require "rack_mini_profiler"

    Rack::MiniProfiler.config.tap do |config|
      config.position = "left"
      # 【position = "left"】
      # バッジの表示位置。"left" → 左上 / "right" → 右上
      # サイドバーが左にある場合は "right" に変えると邪魔にならない。

      config.start_hidden = false
      # 【start_hidden = false】
      # ページを開いたとき最初からバッジを表示する。
      # false → 常に表示（開発中はすぐ確認したいため推奨）

      config.enable_hotwire_turbo_drive_support = true
      # 【enable_hotwire_turbo_drive_support = true】
      # HabitFlow は Hotwire（Turbo Drive）を使用している。
      # このオプションなしだと Turbo によるページ遷移後に
      # バッジが消えたり SQL 計測が引き継がれない問題が起きる。
    end

  rescue LoadError => e
    # gem が見つからない場合は警告だけ出してアプリを起動させる
    # LoadError を rescue しないとアプリ全体が起動できなくなる
    Rails.logger.warn "[rack-mini-profiler] 読み込み失敗: #{e.message}"
    Rails.logger.warn "[rack-mini-profiler] bundle install or docker compose build --no-cache を確認してください"
  end
end