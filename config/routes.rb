# config/routes.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   URLとコントローラーのアクションの対応関係（ルーティング）を定義する。
#   HTTPリクエストが届いたとき、Railsはこのファイルを見て
#   「どのコントローラーのどのアクションを呼び出すか」を決定する。
# ═══════════════════════════════════════════════════════════════════

Rails.application.routes.draw do
  # ---------------------------------------------------------------
  # root
  # ---------------------------------------------------------------
  root "pages#index"

  # ---------------------------------------------------------------
  # Issue #27: カスタムエラーページ確認用ルート（開発環境のみ）
  # ---------------------------------------------------------------
  # Rails.env.development? を使うことで、このブロック内の設定は
  # 開発者のローカル環境だけで有効になる。
  #
  # 【なぜ本番環境で無効にするのか】
  #   本番環境（Render）でこのURLが有効なままだと、
  #   ① 誰でも /errors/404 にアクセスでき、意図しない挙動を生む可能性がある
  #   ② 検索エンジンがエラーページをインデックスしてしまう（SEOノイズ）
  #   ③ セキュリティスキャンツールに不要な口を晒すことになる
  #   これを if Rails.env.development? で囲むだけで上記を防げる。
  if Rails.env.development?
    scope "/errors" do
      # get "/URL", to: "コントローラー名#アクション名", as: :パスヘルパー名
      get "/404", to: "pages#error_404", as: :error_404
      get "/422", to: "pages#error_422", as: :error_422
      get "/500", to: "pages#error_500", as: :error_500
    end
  end

  # ---------------------------------------------------------------
  # resources :users, only: [:new, :create]
  # ---------------------------------------------------------------
  resources :users, only: [ :new, :create ]

  # ---------------------------------------------------------------
  # resource :session
  # ---------------------------------------------------------------
  resource :session, only: [ :new, :create, :destroy ]

  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # ---------------------------------------------------------------
  # get "dashboard"
  # ---------------------------------------------------------------
  get "dashboard", to: "dashboards#index", as: :dashboard

  # ---------------------------------------------------------------
  # resources :habits
  # ---------------------------------------------------------------
  resources :habits, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    # edit と update を追加（B-2: 除外日の変更に対応するため）
    # 【理由】
    #   習慣を作成した後に除外日を変更したいケースが必ずある。
    #   例: 最初は除外日なしで作成 → 後から土日を除外したい。
    #   edit/update がないと作成時しか設定できず実用性が低い。
    resources :habit_records, only: [ :create, :update ]
  end

  # ---------------------------------------------------------------
  # resources :weekly_reflections
  # ---------------------------------------------------------------
  resources :weekly_reflections, only: [ :index, :new, :create, :show ]

  # ============================================================================
  # GoodJob ダッシュボードのルーティング設定
  # ============================================================================
  # ※ catch-all ルート（match "*path"）より必ず前に記述すること
  # Railsのルーティングは上から順に評価されるため、
  # catch-all が先にあると /good_job も 404 になってしまう。
  # 【GoodJob ダッシュボードとは】
  # ブラウザからジョブの実行状況・キュー・エラー履歴を確認できる管理画面。
  # http://localhost:3000/good_job（開発）または
  # https://your-app.onrender.com/good_job（本番・Basic認証後）でアクセスできる。
  #
  # 【環境別のアクセス制御】
  # ┌────────────┬────────────────────────────────────────────┐
  # │ 環境        │ アクセス方法                                │
  # ├────────────┼────────────────────────────────────────────┤
  # │ development │ 認証なしで /good_job にアクセス可能          │
  # │ production  │ 環境変数設定時のみ Basic 認証付きで公開       │
  # │ test        │ ダッシュボードは不要のためマウントしない       │
  # └────────────┴────────────────────────────────────────────┘
  #
  # ============================================================================
  # 開発環境: 認証なしで直接アクセス可能
  # ============================================================================
  #
  # 開発中はローカル環境（localhost）でしかアクセスできないため
  # 認証を省いてシンプルに使える状態にする。
  if Rails.env.development?
    mount GoodJob::Engine => "/good_job"
  end

  # ============================================================================
  # 本番環境: 環境変数が設定されている場合のみ Basic 認証付きで公開
  # ============================================================================
  #
  # 【Basic 認証とは】
  # ブラウザがユーザー名とパスワードを要求するシンプルな認証方式。
  # HTTPS 通信下では盗聴されないため、管理画面の保護として有効。
  # Render の本番環境は force_ssl = true で HTTPS が強制されるため安全。
  #
  # 【環境変数の設定手順（Render ダッシュボード）】
  # 1. Render ダッシュボード → habitflow-web → Environment タブ
  # 2. 以下の環境変数を追加する:
  #    Key: GOOD_JOB_LOGIN    Value: 任意のユーザー名（例: admin）
  #    Key: GOOD_JOB_PASSWORD Value: 任意の強力なパスワード（例: rand(36**20).to_s(36)）
  # 3. 環境変数を設定しない限りダッシュボードは公開されない（二重の安全策）
  #
  # 【Rack::Auth::Basic の仕組み】
  # Rack は Rails の下層にある Web サーバーインターフェース。
  # Rack::Auth::Basic を使うと、マウントしたエンジン（GoodJob）へのリクエストに
  # Basic 認証のレイヤーを追加できる。
  # Lambda（->）で「認証チェックの処理」を定義し、
  # ユーザー名とパスワードが一致したときのみアクセスを許可する。
  if Rails.env.production?
    # 環境変数が両方設定されている場合のみダッシュボードを公開する
    # 設定されていない場合はルート自体が存在しないため 404 になる（安全）
    if ENV["GOOD_JOB_LOGIN"].present? && ENV["GOOD_JOB_PASSWORD"].present?

      # GoodJob::Engine に Basic 認証のラッパーをかけて /good_job にマウントする
      # Rack::Auth::Basic.new(...) → Basic 認証を処理する Rack アプリを生成
      # { |username, password| ... } → 認証ロジックを定義するブロック
      authenticated_good_job = Rack::Auth::Basic.new(GoodJob::Engine) do |username, password|
        # ActiveSupport::SecurityUtils.secure_compare を使う理由:
        # 通常の == 比較は文字列の長さによって処理時間が変わる（タイミング攻撃に脆弱）。
        # secure_compare は常に一定時間で比較するため、タイミング攻撃を防げる。
        ActiveSupport::SecurityUtils.secure_compare(username, ENV["GOOD_JOB_LOGIN"]) &&
          ActiveSupport::SecurityUtils.secure_compare(password, ENV["GOOD_JOB_PASSWORD"])
      end

      # mount に Rack アプリとしてラップしたものを渡す
      mount authenticated_good_job, at: "/good_job"
    end
  end

  # ---------------------------------------------------------------
  # Issue #27: catch-all ルート（必ず最後に記述する）
  # ---------------------------------------------------------------
  # どのルートにもマッチしなかったURLを ErrorsController#not_found に向ける。
  #
  # 【なぜ application#render_404 ではダメなのか】
  #   render_404 は ApplicationController の private メソッドのため、
  #   ルーティングからアクションとして直接呼び出せない。
  #   public アクションを持つ ErrorsController を経由する必要がある。
  #
  # via: :all → GET / POST / DELETE など全HTTPメソッドに対応する。
  # 必ず最後に書くこと（先に書くとすべてのURLが404になる）。
  match "*path", to: "errors#not_found", via: :all

end
