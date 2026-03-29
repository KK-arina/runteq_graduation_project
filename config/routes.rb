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
  # 開発環境専用: カスタムエラーページ確認用ルート
  # ---------------------------------------------------------------
  if Rails.env.development?
    scope "/errors" do
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
  # resources :habits（B-4: アーカイブ関連ルートを追加）
  # ---------------------------------------------------------------
  # 【B-4 での変更点】
  #   habits リソースに 3 つのカスタムルートを追加する。
  #
  # 【collection と member の違い】
  #   collection do ... end:
  #     特定のIDを必要としない「コレクション全体」に対するルート。
  #     URL例: GET /habits/archived
  #     → アーカイブ済み習慣の「一覧」を取得するルート。
  #     → IDは不要（どのユーザーのアーカイブ一覧かはセッションで判断）。
  #
  #   member do ... end:
  #     特定の1件（:id）に対するルート。
  #     URL例: POST   /habits/:id/archive
  #            PATCH  /habits/:id/unarchive
  #     → 「この習慣（:id）をアーカイブ/復元する」という操作。
  #     → IDが必要（どの習慣を操作するかを特定するため）。
  #
  # 【生成されるパスヘルパーと URL】
  #   archived_habits_path     → GET    /habits/archived         → habits#archived
  #   archive_habit_path(id)   → POST   /habits/:id/archive      → habits#archive
  #   unarchive_habit_path(id) → PATCH  /habits/:id/unarchive    → habits#unarchive

  resources :habits, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    # collection: 特定IDなし、習慣の「一覧」に対する操作
    collection do
      # GET /habits/archived → habits#archived
      # アーカイブ済み習慣の一覧ページ（8-2番画面）
      get :archived
    end

    # member: 特定IDあり、個別習慣に対する操作
    member do
      # POST /habits/:id/archive → habits#archive
      # 指定した習慣をアーカイブする
      post :archive

      # PATCH /habits/:id/unarchive → habits#unarchive
      # 指定した習慣のアーカイブを解除して復元する
      patch :unarchive
    end

    # 除外日設定のためのネストルート（B-2 既存）
    resources :habit_records, only: [ :create, :update ]
  end

  # ---------------------------------------------------------------
  # resources :weekly_reflections
  # ---------------------------------------------------------------
  resources :weekly_reflections, only: [ :index, :new, :create, :show ]

  # ---------------------------------------------------------------
  # GoodJob ダッシュボード（開発環境）
  # ---------------------------------------------------------------
  if Rails.env.development?
    mount GoodJob::Engine => "/good_job"
  end

  # ---------------------------------------------------------------
  # GoodJob ダッシュボード（本番環境: Basic認証付き）
  # ---------------------------------------------------------------
  if Rails.env.production?
    if ENV["GOOD_JOB_LOGIN"].present? && ENV["GOOD_JOB_PASSWORD"].present?
      authenticated_good_job = Rack::Auth::Basic.new(GoodJob::Engine) do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(username, ENV["GOOD_JOB_LOGIN"]) &&
          ActiveSupport::SecurityUtils.secure_compare(password, ENV["GOOD_JOB_PASSWORD"])
      end
      mount authenticated_good_job, at: "/good_job"
    end
  end

  # ---------------------------------------------------------------
  # catch-all ルート（必ず最後に記述する）
  # ---------------------------------------------------------------
  match "*path", to: "errors#not_found", via: :all
end