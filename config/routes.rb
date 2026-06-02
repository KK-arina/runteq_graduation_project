# config/routes.rb
#
# ============================================================
# F-1 追加: OmniAuth Google コールバックルートを追加
# F-2 追加: OmniAuth LINE コールバックルートを追加
# F-3 追加: 利用規約・プライバシーポリシー・OAuth同意ルートを追加
# F-4 追加: パスワードリセット機能のルーティングを追加
# G-3 追加: 通知設定ページのルーティングを追加
# ============================================================

Rails.application.routes.draw do
  root "pages#index"

  # ============================================================
  # 開発環境専用ルート
  # ============================================================
  if Rails.env.development?
    scope "/errors" do
      get "/404", to: "pages#error_404", as: :error_404
      get "/422", to: "pages#error_422", as: :error_422
      get "/500", to: "pages#error_500", as: :error_500
    end

    mount LetterOpenerWeb::Engine, at: "/letter_opener"
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
  get "/terms",   to: "pages#terms",   as: :terms
  get "/privacy", to: "pages#privacy", as: :privacy

  # ============================================================
  # F-4 追加: パスワードリセット機能のルーティング
  # ============================================================
  resources :password_resets, only: [:new, :create, :edit, :update]

  # ============================================================
  # F-3 追加: OAuth 初回ログイン時の利用規約同意ルート
  # ============================================================
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

  get "/auth/failure",
      to:  "omniauth_callbacks#failure",
      as:  :omniauth_failure

  scope "/onboarding", controller: :onboardings do
    get  "step5",    action: :step5,    as: :onboarding_step5
    post "complete", action: :complete, as: :onboarding_complete
    post "skip",     action: :skip,     as: :onboarding_skip
  end

# 変更前:
#   member do
#     get   :notification_settings,
#           to: "user_settings#notification_settings"
#     patch :update_notification_settings,
#           to: "user_settings#update_notification_settings"
#   end
#
# 変更後:
#   member do + collection で分けるのではなく、
#   scope を使って GET と PATCH を同じパス /settings/notification_settings に向ける。
#
# 【なぜ member の patch が /update_notification_settings になるのか】
#   Rails の member は「アクション名がそのままパスになる」。
#   patch :update_notification_settings → /settings/update_notification_settings
#   これを /settings/notification_settings にするには
#   path: を明示するか、GET と同じアクション名にする必要がある。
#
# 【解決策】
#   PATCH も path: "notification_settings" を指定して
#   GET と同じ URL /settings/notification_settings を使うようにする。

  resource :settings, only: %i[show destroy] do
    member do
      get   :notification_settings,
            to: "user_settings#notification_settings"
      # patch の path を明示して GET と同じ URL にする
      # path: "notification_settings" を指定することで
      # /settings/update_notification_settings ではなく
      # /settings/notification_settings (PATCH) になる
      patch :update_notification_settings,
            to:   "user_settings#update_notification_settings",
            path: "notification_settings"
    end
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