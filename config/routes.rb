# config/routes.rb

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

  get "dashboard", to: "dashboards#index", as: :dashboard

  # ---------------------------------------------------------------
  # resources :tasks（C-2: 完了チェック・アーカイブ機能を追加）
  # ---------------------------------------------------------------
  # 【C-3 変更点】
  #   only に :destroy を追加した。
  #   生成されるルート:
  #     DELETE /tasks/:id → tasks#destroy
  #     → task_path(task) で "/tasks/1" のようなURLを生成する
  #     → button_to task_path(task), method: :delete で呼び出す

  resources :tasks, only: [ :index, :new, :create, :destroy ] do
    member do
      # PATCH /tasks/:id/toggle_complete → タスクの完了↔未完了を切り替える
      patch :toggle_complete

      # PATCH /tasks/:id/archive → 完了タスクを個別にアーカイブする
      patch :archive
    end

    collection do
      # PATCH /tasks/archive_all_done → 完了タスクを一括アーカイブする
      patch :archive_all_done
    end
  end

  resources :habits, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    collection do
      get  :archived
      patch :sort
    end

    member do
      post  :archive
      patch :unarchive
    end

    resources :habit_records, only: [ :create, :update ]
  end

  resources :weekly_reflections, only: [ :index, :new, :create, :show ]

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