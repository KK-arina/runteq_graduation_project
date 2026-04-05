# config/importmap.rb
# （B-6: Sortable.js を追加）

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

pin "controllers/habit_checkbox_controller", to: "controllers/habit_checkbox_controller.js"

# ============================================================
# B-6: Sortable.js（Drag & Drop ライブラリ）
# ============================================================
#
# 【CDN ではなくローカルファイルを使う理由】
#   CDN の URL は正常に読み込めているが、
#   importmap 経由での動的インポートが
#   Docker 環境や CSP（コンテンツセキュリティポリシー）の
#   制限で動作しない場合がある。
#   vendor/javascript/ に配置したローカルファイルを使うことで
#   ネットワーク依存をなくし確実に動作させる。
#
# 【vendor/javascript/ とは】
#   Rails 7 から importmap 用の外部ライブラリを置く場所として
#   vendor/javascript/ ディレクトリが用意されている。
#   ここに置いたファイルは自動的にアセットパイプラインに含まれる。
pin "Sortable", to: "sortable.esm.js"

pin "controllers/habit_sort_controller", to: "controllers/habit_sort_controller.js"