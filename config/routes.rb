# config/routes.rb
#
# ============================================================
# F-1 追加: OmniAuth Google コールバックルートを追加
# F-2 追加: OmniAuth LINE コールバックルートを追加
# F-3 追加: 利用規約・プライバシーポリシー・OAuth同意ルートを追加
# F-4 追加: パスワードリセット機能のルーティングを追加
# ============================================================

Rails.application.routes.draw do
  root "pages#index"

  # ============================================================
  # 開発環境専用ルート
  # ============================================================
  #
  # 【なぜ1つのブロックにまとめるのか】
  #   if Rails.env.development? を複数箇所に書くと、
  #   同じ :as 名（error_404 など）が2回定義されて
  #   「Invalid route name, already in use」エラーになる。
  #   開発環境専用のルートは1つのブロックにまとめることで
  #   この問題を防ぐ。
  if Rails.env.development?
    # エラーページ確認用ルート（開発環境でのみ直接アクセス可能）
    scope "/errors" do
      get "/404", to: "pages#error_404", as: :error_404
      get "/422", to: "pages#error_422", as: :error_422
      get "/500", to: "pages#error_500", as: :error_500
    end

    # F-4修正: letter_opener_web のメール確認 UI をマウントする
    #
    # 【役割】
    #   http://localhost:3000/letter_opener にアクセスすることで
    #   開発環境で送信されたメールの一覧・内容を確認できる。
    #   Docker 環境では letter_opener（自動ブラウザ起動）が使えないため、
    #   この Web UI を使って代替する。
    mount LetterOpenerWeb::Engine, at: "/letter_opener"

    # GoodJob の管理画面（ジョブの実行状況を確認できる）
    mount GoodJob::Engine => "/good_job"
  end

  resources :users, only: [ :new, :create ]

  resource :session, only: [ :new, :create, :destroy ]

  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # ============================================================
  # F-3 追加: 利用規約・プライバシーポリシー静的ページ
  # ============================================================
  #
  # GET /terms:
  #   利用規約ページ。PagesController#terms が処理する。
  #   未ログインでも閲覧できる（before_action :require_login を付けていない）。
  get "/terms",   to: "pages#terms",   as: :terms

  # GET /privacy:
  #   プライバシーポリシーページ。PagesController#privacy が処理する。
  #   未ログインでも閲覧できる。
  get "/privacy", to: "pages#privacy", as: :privacy

  # ============================================================
  # F-4 追加: パスワードリセット機能のルーティング
  # ============================================================
  #
  # resources :password_resets で以下のルートが生成される:
  #   GET  /password_resets/new        → new    （23番画面: メアドフォーム）
  #   POST /password_resets            → create  （メール送信）
  #   GET  /password_resets/:id/edit   → edit    （26番画面: 新パスワード入力）
  #   PATCH/PUT /password_resets/:id  → update  （パスワード変更処理）
  #
  # only: で不要なアクション（show, index, destroy）を除外する。
  # :id の部分には生のトークン文字列が入る（数値IDではない）。
  resources :password_resets, only: [:new, :create, :edit, :update]

  # ============================================================
  # F-3 追加: OAuth 初回ログイン時の利用規約同意ルート
  # ============================================================
  #
  # GET /terms_agreement:
  #   OAuth 初回ログイン後に表示する同意確認ページ。
  #   TermsAgreementController#show が処理する。
  #
  # POST /terms_agreement:
  #   同意チェックボックスを送信して terms_agreed_at を記録する。
  #   TermsAgreementController#agree が処理する。
  #   as: を付けると terms_agreement_agree_path ヘルパーが生成される。
  get  "/terms_agreement", to: "terms_agreement#show",  as: :terms_agreement
  post "/terms_agreement", to: "terms_agreement#agree", as: :terms_agreement_agree

  # ============================================================
  # F-1 追加: OmniAuth Google コールバック & 失敗ルート
  # ============================================================
  get "/auth/google_oauth2/callback",
      to:  "omniauth_callbacks#google",
      as:  :omniauth_google_callback

  # ============================================================
  # F-2 追加: OmniAuth LINE コールバックルート
  # ============================================================
  get "/auth/line_v2_1/callback",
      to:  "omniauth_callbacks#line",
      as:  :omniauth_line_callback

  # GET /auth/failure:
  #   OmniAuth がエラーと判定した場合のフォールバック。
  get "/auth/failure",
      to:  "omniauth_callbacks#failure",
      as:  :omniauth_failure

  scope "/onboarding", controller: :onboardings do
    get  "step5",    action: :step5,    as: :onboarding_step5
    post "complete", action: :complete, as: :onboarding_complete
    post "skip",     action: :skip,     as: :onboarding_skip
  end

  get "dashboard", to: "dashboards#index", as: :dashboard

  resource :user_purpose, only: [:show, :new, :create, :edit, :update] do
    member do
      post :retry_analysis
      get  :ai_result
      post :apply_proposals
    end
  end

  resources :tasks, only: [ :index, :new, :create, :destroy ] do
    member do
      patch :toggle_complete
      patch :archive
      get   :ai_edit
      patch :ai_update
    end

    collection do
      patch :archive_all_done
    end
  end

  resources :habits, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    collection do
      get   :archived
      patch :sort
    end

    member do
      post  :archive
      patch :unarchive
      get   :ai_edit
      patch :ai_update
    end

    resources :habit_records, only: [ :create, :update ]
  end

  resources :weekly_reflections, only: [:index, :new, :create, :show] do
    collection do
      post :complete_without_ai
      post :confirm_proposals
    end
  end

  # ============================================================
  # 本番環境の GoodJob 管理画面（Basic認証付き）
  # ============================================================
  if Rails.env.production?
    if ENV["GOOD_JOB_LOGIN"].present? && ENV["GOOD_JOB_PASSWORD"].present?
      authenticated_good_job = Rack::Auth::Basic.new(GoodJob::Engine) do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(username, ENV["GOOD_JOB_LOGIN"]) &&
          ActiveSupport::SecurityUtils.secure_compare(password, ENV["GOOD_JOB_PASSWORD"])
      end
      mount authenticated_good_job, at: "/good_job"
    end
  end

  match "*path", to: "errors#not_found", via: :all
end