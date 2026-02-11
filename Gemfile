# ==================== Gemfile ====================
# このファイルは、Railsアプリケーションで使用するgemを管理します
# gem: Rubyのライブラリ・パッケージのこと
# bundle install コマンドで、ここに記載されたgemがインストールされます

# ==================== Gemの取得元 ====================
# RubyGemsの公式リポジトリからgemをダウンロード
source "https://rubygems.org"

# ==================== Rubyバージョン指定 ====================
# このアプリケーションで使用するRubyのバージョン
# Docker環境では、Dockerfileで指定したバージョンと一致させる
ruby "3.4.7"

# ==================== フレームワーク ====================

# Rails: Webアプリケーションフレームワーク
# ~> 7.2.3: バージョン7.2.x系の最新版を使用（7.3.0は使わない）
gem "rails", "~> 7.2.3"

# ==================== アセットパイプライン ====================

# sprockets-rails: CSS/JavaScriptファイルを管理・最適化
# Railsの伝統的なアセット管理システム
gem "sprockets-rails"

# ==================== データベース ====================

# pg: PostgreSQLデータベースへの接続用gem
# ~> 1.1: バージョン1.1.x系を使用
gem "pg", "~> 1.1"

# ==================== Webサーバー ====================

# Puma: 高性能なRails用Webサーバー
# >= 5.0: バージョン5.0以上を使用
# 本番環境でも開発環境でも使用
gem "puma", ">= 5.0"

# ==================== フロントエンド（JavaScript） ====================

# importmap-rails: JavaScriptをESモジュールとして管理
# Node.jsやwebpackを使わずにJavaScriptを扱える
gem "importmap-rails"

# turbo-rails: Hotwireの一部、ページ遷移を高速化
# SPAのような体験をJavaScriptなしで実現
gem "turbo-rails"

# stimulus-rails: Hotwireの一部、軽量なJavaScriptフレームワーク
# 必要な部分だけJavaScriptで動きを追加
gem "stimulus-rails"

# ==================== フロントエンド（CSS） ====================

# tailwindcss-rails: Tailwind CSSをRailsで使用
# ユーティリティファーストのCSSフレームワーク
gem "tailwindcss-rails"

# ==================== API・JSON ====================

# jbuilder: JSONレスポンスを簡単に構築
# APIエンドポイントを作る際に便利
gem "jbuilder"

# ==================== 認証 ====================

# bcrypt: パスワードをハッシュ化して安全に保存
# has_secure_passwordメソッドを使用する際に必須
# Issue #5で使用開始
gem "bcrypt", "~> 3.1.7"

# ==================== パフォーマンス ====================

# bootsnap: アプリケーションの起動を高速化
# キャッシュを使って読み込み時間を短縮
# config/boot.rbで自動的に読み込まれる
gem "bootsnap", require: false

# ==================== タイムゾーン ====================

# tzinfo-data: タイムゾーン情報を提供
# WindowsやJRuby環境で必須（Linux/Macでは不要だが害もない）
gem "tzinfo-data", platforms: %i[ windows jruby ]

# ==================== 開発環境・テスト環境のみ ====================
# bundle install --without development test で除外可能

group :development, :test do
  # debug: デバッグ用gem
  # binding.break でコードを一時停止してデバッグ可能
  # platforms: %i[ mri windows ]: 標準Ruby（MRI）とWindows環境のみ
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # brakeman: セキュリティ脆弱性を自動検出
  # SQLインジェクション、XSSなどの脆弱性をチェック
  # require: false: 自動読み込みしない（コマンドラインツールとして使用）
  gem "brakeman", require: false

  # rubocop-rails-omakase: Railsのコーディング規約チェック
  # コードの品質を保つための静的解析ツール
  # require: false: 自動読み込みしない（コマンドラインツールとして使用）
  gem "rubocop-rails-omakase", require: false
end

# ==================== 開発環境のみ ====================

group :development do
  # web-console: ブラウザ上でRailsコンソールを使用
  # エラー画面で直接コードを実行してデバッグ可能
  gem "web-console"
end

# ==================== テスト環境のみ ====================

group :test do
  # capybara: E2Eテスト（ブラウザ操作テスト）用gem
  # ユーザーの操作をシミュレートしてテスト
  gem "capybara"

  # selenium-webdriver: ブラウザ自動操作ツール
  # Capybaraと組み合わせて、実際のブラウザでテスト
  gem "selenium-webdriver"
end

# ==================== コメントアウト（未使用）のgem ====================

# Redis: インメモリデータベース
# Action Cable（WebSocket）やキャッシュで使用
# 現在は不要なのでコメントアウト
# gem "redis", ">= 4.0.1"

# Kredis: Redisをより便利に使うためのgem
# 現在は不要なのでコメントアウト
# gem "kredis"

# image_processing: 画像のリサイズ・変換
# Active Storageで画像を扱う際に必要
# 現在は不要なのでコメントアウト
# gem "image_processing", "~> 1.2"
