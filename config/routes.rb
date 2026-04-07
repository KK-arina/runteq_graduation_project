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
  # 【C-2 での変更点】
  #   C-1 では only: [:index, :new, :create] だったが、
  #   C-2 で以下のカスタムアクションを member に追加する。
  #
  # 【member を使う理由】
  #   「特定の1件（:id）」に対する操作なので member が適切。
  #   collection は「コレクション全体」に対する操作（例: 並び替え）に使う。
  #
  # 【生成されるルートとパスヘルパー】
  #   PATCH /tasks/:id/toggle_complete → tasks#toggle_complete
  #     → toggle_complete_task_path(task)
  #     → チェックボックスで完了↔未完了を切り替える
  #
  #   PATCH /tasks/:id/archive         → tasks#archive
  #     → archive_task_path(task)
  #     → 完了タスクを個別にアーカイブする
  #
  #   PATCH /tasks/archive_all_done    → tasks#archive_all_done
  #     → archive_all_done_tasks_path
  #     → 完了タスクを一括アーカイブする
  #     → collection を使う理由: 特定の1件ではなく
  #       「完了済み全件」に対する操作だから
  resources :tasks, only: [ :index, :new, :create ] do
    member do
      # PATCH /tasks/:id/toggle_complete
      # チェックボックスタップで todo ↔ done を切り替える
      patch :toggle_complete

      # PATCH /tasks/:id/archive
      # 個別アーカイブボタンで status を archived に変更する
      patch :archive
    end

    collection do
      # PATCH /tasks/archive_all_done
      # 「すべてアーカイブ」ボタンで完了済み全件を一括アーカイブ
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