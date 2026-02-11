# ==================== ビルドステージ ====================
# 本番環境用のイメージを作成するための最初のステージ
# ここでは依存関係のインストールとアセットのプリコンパイルを行う

# ARG: ビルド時に指定できる変数（デフォルト値を設定）
ARG RUBY_VERSION=3.4.7
# FROM: ベースイメージを指定（Ruby公式のslimイメージ）
FROM ruby:$RUBY_VERSION-slim AS base

# 作業ディレクトリを設定
WORKDIR /rails

# 環境変数の設定
# RAILS_ENV="production": 本番環境として実行
# BUNDLE_DEPLOYMENT="1": Gemfile.lockを使用して厳密なバージョン管理
# BUNDLE_PATH="/usr/local/bundle": Gemのインストール先
# BUNDLE_WITHOUT="development:test": 開発・テスト用のGemをインストールしない
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# ==================== ビルドステージ ====================
FROM base AS build

# ビルドに必要なパッケージをインストール
# build-essential: C/C++コンパイラ（ネイティブ拡張のGem用）
# git: Gitリポジトリから直接Gemをインストールする場合に必要
# libpq-dev: PostgreSQL開発ライブラリ（pg gem用）
# pkg-config: パッケージの設定情報を取得
# 追加: libvips (画像処理用) をビルド時にも念のため追加
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    pkg-config \
    curl \
    libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node.js 20.x のインストール（Tailwind CSSのビルドに必要）
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn

# Gemのインストール
# Gemfile.lockに記載された正確なバージョンをインストール
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# アプリケーションコードをコピー
COPY . .

# アセットのプリコンパイル
# SECRET_KEY_BASE_DUMMY=1: ダミーのシークレットキー（プリコンパイル時のみ使用）
# assets:precompile: CSS/JSを最適化して本番用にビルド
# tailwindcss:build: Tailwind CSSをビルド
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails tailwindcss:build

# ==================== 本番ステージ ====================
# 実際に本番環境で実行されるイメージ
# ビルドステージで作成したファイルを軽量なイメージにコピー
FROM base

# 実行時に必要な最小限のパッケージをインストール
# postgresql-client: PostgreSQLクライアント（psqlコマンド）
# libjemalloc2: メモリ管理の最適化
# 追加: libvips (画像処理), tzdata (タイムゾーン)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    postgresql-client \
    libjemalloc2 \
    libvips \
    tzdata && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# 非rootユーザーの作成（セキュリティ向上）
# rails: ユーザー名
# --disabled-password: パスワード認証を無効化
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails /rails

# railsユーザーに切り替え
USER rails:rails

# ビルドステージからGemをコピー
COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle

# ビルドステージからアプリケーションコードをコピー
COPY --from=build --chown=rails:rails /rails /rails

# エントリーポイントスクリプトをコピー
COPY --from=build --chown=rails:rails /rails/bin/docker-entrypoint /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint

# エントリーポイントを設定
ENTRYPOINT ["docker-entrypoint"]

# ポート3000を公開
EXPOSE 3000

# 起動コマンド
# -b 0.0.0.0: すべてのIPアドレスからの接続を許可（Docker必須）
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
