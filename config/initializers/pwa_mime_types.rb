# frozen_string_literal: true

# config/initializers/pwa_mime_types.rb
#
# ==============================================================================
# ホーム画面に追加（PWA）: マニフェストファイルの MIME タイプを登録する
# ==============================================================================
#
# 【このファイルの役割】
#   public/pwa/manifest-v1.webmanifest を返すときの Content-Type を
#   "application/manifest+json"（W3C の仕様で決められた正式な種類）にする。
#
# 【なぜ必要なのか】
#   public/ のファイルは、Rails のコントローラーではなく
#   ActionDispatch::Static（Rack のミドルウェア）が返している。
#   ActionDispatch::Static は拡張子から Content-Type を決めるときに
#   Rack::Mime::MIME_TYPES という対応表を使う。
#   この表に ".webmanifest" が無いバージョンの Rack だと
#   "application/octet-stream"（ただのバイナリ）として返されてしまう。
#
# 【||= を使う理由】
#   Rack がすでに登録していれば、その値をそのまま使う（上書きしない）。
#   登録されていないときだけ追加するので、Rack のバージョンが変わっても安全。
#
# 【Neon（DB）への影響】
#   起動時に Ruby の Hash に1件追加するだけで、DB には一切アクセスしない。
# ==============================================================================
Rack::Mime::MIME_TYPES[".webmanifest"] ||= "application/manifest+json"
