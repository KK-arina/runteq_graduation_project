require "active_support/core_ext/integer/time"

Rails.application.configure do
  # ==================== 基本設定 ====================
  # キャッシュを有効化（本番環境ではパフォーマンス向上のため必須）
  config.cache_classes = true
  
  # Eager Loading: アプリケーション起動時にすべてのコードを読み込む
  # 本番環境では必須（起動は遅くなるが、リクエスト時のパフォーマンスが向上）
  config.eager_load = true
  
  # ==================== 静的ファイル配信 ====================
  # 環境変数 RAILS_SERVE_STATIC_FILES が設定されている場合、静的ファイルを配信
  # Renderでは必須（Nginxなどのリバースプロキシがないため）
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  
  # ==================== ログ設定 ====================
  # ログレベル: :info（本番環境では詳細すぎないレベル）
  config.log_level = :info
  
  # ログを標準出力に出力（RenderやHerokuなどのPaaS必須）
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
  
  # ログのタグ付け（リクエストごとにIDを付与して追跡しやすく）
  config.log_tags = [ :request_id ]
  
  # ↓ 追加: RenderのSSLプロキシを正しく扱うための設定
  config.assume_ssl = true
  config.force_ssl = true
  
  # その他の設定はRailsデフォルトのまま
end
