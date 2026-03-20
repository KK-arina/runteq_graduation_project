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
# ~> 7.0 の意味:
# 「7.0 以上 8.0 未満」を許可する。
# ログで Puma 7.1.0 が動作していることが確認できているため 7.x 系に固定する。
# >= 5.0 では 6系・7系・8系すべてインストール対象になり、
# メジャーバージョンアップで予期しない挙動変化が起きるリスクがある。
gem "puma", "~> 7.0"

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

# ==================== 非同期ジョブ処理 ====================
#
# ============================================================
# Issue #A-3: GoodJob 導入
# ============================================================
#
# 【GoodJobとは何か】
# Railsには「ActiveJob」という非同期処理の統一インターフェースがある。
# GoodJobはそのActiveJobのバックエンド（実際の実行エンジン）として機能する。
#
# 【なぜGoodJobを選んだのか】
# 非同期処理のバックエンドには複数の選択肢がある:
#   - Sidekiq  → 高性能だが「Redis」という別のデータベースが必要
#   - Resque   → 同様に Redis が必要
#   - GoodJob  → PostgreSQL のみで動作。Redis 不要！
#
# HabitFlow は Render（無料）+ Neon PostgreSQL で運用している。
# GoodJob なら既存の PostgreSQL をそのまま使えるため構成がシンプル。
#
# 【GoodJobが担う機能】
#   - AI 分析ジョブ（PMVV・週次振り返りのAI分析を非同期実行）
#   - LINE 通知送信（タスクのアラーム通知）
#   - CSV エクスポート（大量データの非同期生成）
#   - ストリーク計算バッチ（毎日AM4:05に全ユーザー対象）
#   - AI 使用回数の月次リセット（毎月1日00:00）
#   - 日次通知カウントリセット（毎日00:05）
#
# 【バージョンを固定しない理由】
# GoodJob はバージョンによって設定 API とDBスキーマが変わる:
#   3.3.x   → Rails 7.2 の新API（enqueue_after_transaction_commit?）に未対応
#   3.30.1  → 3.x 系の最終安定版
#   3.99.x  → 4.x への移行版
#   4.x     → Rails 7.2 / 8.x 正式対応。最新の設計。← これを使用
#
# バージョンを固定しないことで:
#   - セキュリティパッチが自動で適用される
#   - Rails のアップグレード時に追従しやすい
#
# 【4.x を使う際の注意点】
# GoodJob 4.x では DBスキーマに新しいカラムが追加されている。
# good_job:install（初回）ではなく good_job:update でマイグレーションを追加する。
gem "good_job"

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

  # ==============================================================================
  # minitest バージョン固定
  # ==============================================================================
  #
  # 【なぜ固定するのか】
  # GoodJob 3.3.x が minitest 6.x を依存関係として引き込む。
  # Rails 7.2 の test ヘルパーは minitest 5.x を前提としており、
  # 6.x が入ると run メソッドの引数が変わり
  # 「wrong number of arguments (given 3, expected 1..2)」エラーが発生する。
  # ~> 5.1 で 5.x 系の最新版に固定してバージョン競合を防ぐ。
  gem "minitest", "~> 5.1"
end

# ==================== 開発環境のみ ====================

group :development do
  # web-console: ブラウザ上でRailsコンソールを使用
  # エラー画面で直接コードを実行してデバッグ可能
  gem "web-console"

  # ============================================================
  # Issue #29: パフォーマンス最適化
  # ============================================================
  # bullet: N+1問題（必要以上にDBクエリが発行される問題）を
  # 自動で検出してくれるgemです。
  #
  # 【N+1問題とは？】
  # 例えば10件の習慣を表示するとき、各習慣の記録を
  # ループの中で毎回DBから取得すると「1(習慣一覧) + 10(記録取得)」
  # = 11回のSQLが発行されてしまいます。これを N+1 問題と呼びます。
  # includesを使って事前に一括取得すれば「2回」のSQLで済みます。
  #
  # 【なぜ development グループのみか？】
  # Bulletは開発中にN+1を検出するためのツールです。
  # 本番環境で動かすとパフォーマンスが落ちるため、開発環境のみに限定します。
  gem "bullet"
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
# GoodJobを使うためRedisは不要
# gem "redis", ">= 4.0.1"

# Kredis: Redisをより便利に使うためのgem
# 現在は不要なのでコメントアウト
# gem "kredis"

# image_processing: 画像のリサイズ・変換
# Active Storageで画像を扱う際に必要
# 現在は不要なのでコメントアウト
# gem "image_processing", "~> 1.2"