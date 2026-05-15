# config/routes.rb
#
# 【E-3 変更点】
#   weekly_reflections の collection に以下を追加:
#     post :confirm_proposals  → AI提案を確定してDBに保存する
#     delete :dismiss_proposal → 個別提案を提案リストから除外する
#
# 【なぜ collection を使うのか】
#   confirm_proposals は特定の1件ではなく
#   「今週の振り返りに紐づく全提案」を対象とする操作のため
#   :id パラメータが不要 → collection が適切。
#   member は /resources/:id/action の形式（:id が必須）。

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

  # ============================================================
  # E-3 変更: weekly_reflections の collection に AI提案確定を追加
  # ============================================================
  resources :weekly_reflections, only: [:index, :new, :create, :show] do
    collection do
      post :complete_without_ai

      # ── E-3 追加 ────────────────────────────────────────────────────────
      #
      # confirm_proposals:
      #   POST /weekly_reflections/confirm_proposals
      #   → weekly_reflections#confirm_proposals
      #
      #   「来週の計画を確定」ボタンの送信先。
      #   AI提案（habits/tasks）を正式にDBへ保存し、
      #   ai_generated=true をタスクにセットする。
      #   ルートヘルパー: confirm_proposals_weekly_reflections_path
      #
      # ロック解除について:
      #   WeeklyReflection の complete! はすでに create アクションで
      #   呼ばれているため、ここではロック解除は不要。
      #   ただし、is_locked が false になっているかの確認は行う。
      post :confirm_proposals
      # ────────────────────────────────────────────────────────────────────
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