# config/routes.rb
#
# ============================================================
# F-1 追加: OmniAuth Google コールバックルートを追加
# F-2 追加: OmniAuth LINE コールバックルートを追加
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
  # F-1 追加: OmniAuth Google コールバック & 失敗ルート
  # ============================================================
  #
  # GET /auth/google_oauth2/callback:
  #   Google 認証完了後に Google からリダイレクトされるエンドポイント。
  get "/auth/google_oauth2/callback",
      to:  "omniauth_callbacks#google",
      as:  :omniauth_google_callback

  # ============================================================
  # F-2 追加: OmniAuth LINE コールバックルート
  # ============================================================
  #
  # 【重要】omniauth-line-v2_1 gem のプロバイダ名は :line_v21 のため、
  #   OmniAuth が自動生成するコールバック URL は /auth/line_v21/callback になる。
  #   routes.rb もこれに合わせて /auth/line_v21/callback を定義する。
  get "/auth/line_v2_1/callback",
      to:  "omniauth_callbacks#line",
      as:  :omniauth_line_callback

  # GET /auth/failure:
  #   OmniAuth がエラーと判定した場合のフォールバックエンドポイント。
  #   Google/LINE いずれかの認証失敗でもここに来る。
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