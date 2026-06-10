# config/routes.rb
#
# ==============================================================================
# ルーティング設定（G-6 更新: プロフィール編集・タイムゾーン・LINE連携解除を追加）
# ==============================================================================
Rails.application.routes.draw do
  root "pages#index"

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

  get "/terms",   to: "pages#terms",   as: :terms
  get "/privacy", to: "pages#privacy", as: :privacy

  resources :password_resets, only: [:new, :create, :edit, :update]

  get  "/terms_agreement", to: "terms_agreement#show",  as: :terms_agreement
  post "/terms_agreement", to: "terms_agreement#agree", as: :terms_agreement_agree

  get "/auth/google_oauth2/callback",
      to:  "omniauth_callbacks#google",
      as:  :omniauth_google_callback

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

  resource :settings, only: %i[show destroy] do
    member do
      # G-3 由来: 通知設定
      get   :notification_settings,
            to: "user_settings#notification_settings"
      patch :update_notification_settings,
            to:   "user_settings#update_notification_settings",
            path: "notification_settings"

      # G-4 由来: お休みモード
      get    :rest_mode,
             to: "user_settings#rest_mode"
      post   :start_rest_mode,
             to:   "user_settings#start_rest_mode",
             path: "rest_mode"
      delete :stop_rest_mode,
             to:   "user_settings#stop_rest_mode",
             path: "rest_mode"

      # G-5 由来: CSVエクスポート
      # 【GETではなくPOSTを使う理由】
      #   CSVエクスポートはGoodJobへのジョブ登録という副作用があるため、
      #   副作用のあるリクエストにはPOSTを使うのがRESTの原則。
      post :export_csv_habit_records,
           to:   "csv_exports#habit_records",
           path: "export_csv/habit_records"
      post :export_csv_tasks,
           to:   "csv_exports#tasks",
           path: "export_csv/tasks"
      post :export_csv_weekly_reflections,
           to:   "csv_exports#weekly_reflections",
           path: "export_csv/weekly_reflections"

      # G-5 由来: CSVダウンロード（メールリンクはGETのみ有効なためGET）
      get :download_csv,
          to:   "csv_exports#download",
          path: "download_csv"

      # ============================================================
      # G-6 追加: プロフィール編集・タイムゾーン・LINE連携解除
      # ============================================================
      #
      # 【patch :update_profile を使う理由】
      #   PATCHは「既存リソースの一部を更新する」HTTP動詞。
      #   ユーザー名（nameカラム）だけを変更するため、PUT（全体更新）より
      #   PATCHが意味論的に正確。
      #
      # 【patch :update_timezone を使う理由】
      #   user_settingsテーブルのtime_zoneカラムだけを変更するため同様にPATCH。
      #
      # 【delete :disconnect_line を使う理由】
      #   「LINE連携情報（line_user_id）を削除する」操作なのでDELETE。
      #   RESTful設計として削除操作にはDELETEメソッドを使う。
      patch  :update_profile,
             to:   "settings#update_profile",
             path: "profile"
      patch  :update_timezone,
             to:   "settings#update_timezone",
             path: "timezone"
      delete :disconnect_line,
             to:   "settings#disconnect_line",
             path: "line"
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