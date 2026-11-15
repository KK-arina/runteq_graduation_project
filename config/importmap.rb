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
#
# ── Lighthouse 対応: preload: false ──────────────────────────────
# preload: false を付けると、javascript_importmap_tags が全ページの <head> に
# <link rel="modulepreload">（先読みの指示）を出さなくなる。
# SortableJS は習慣一覧でしか使わないため、habit_sort_controller.js の
# import("Sortable")（動的 import）で、使うときだけ読み込む。
# pin 自体は残すので、import("Sortable") は今までどおり読み込み先を見つけられる。
pin "Sortable", to: "sortable.esm.js", preload: false

# ── Lighthouse 対応: preload: false ──────────────────────────────
# chart.js（約 60KB）はグラフ・進捗分析ページでしか使わないため、全ページでの先読みをやめ、
# analytics_chart_controller.js の import("chart.js")（動的 import）で、使うときだけ読み込む。
# 実体は vendor/javascript/chart.js.js（UMD 版。読み込むと window.Chart が作られる）。
pin "chart.js", preload: false # @4.5.1
