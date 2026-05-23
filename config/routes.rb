# config/routes.rb
#
# ============================================================
# F-1 追加: OmniAuth Google コールバックルートを追加
# F-2 追加: OmniAuth LINE コールバックルートを追加
# F-3 追加: 利用規約・プライバシーポリシー・OAuth同意ルートを追加
# ============================================================

Rails.application.routes.draw do
  root "pages#index"

  if Rails.env.development?
    scope "/errors" do
      get "/404", to: "pages#error_404", as: :error_404
      get "/422", to: "pages#error_422", as: :error_422
      get "/500", to: "pages#error_500", as: :error_500
    end
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

  if Rails.env.development?
    mount GoodJob::Engine => "/good_job"
  end

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