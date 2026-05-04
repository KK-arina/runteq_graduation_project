# config/routes.rb
#
# 【D-8 変更点】
#   habits リソースの member ブロックに ai_edit / ai_update を追加する。
#
# 【変更前】
#   member do
#     post  :archive
#     patch :unarchive
#   end
#
# 【変更後】
#   member do
#     post  :archive
#     patch :unarchive
#     get   :ai_edit    ← 追加
#     patch :ai_update  ← 追加
#   end
#
# 【なぜ member を使うのか】
#   member は /habits/:id/アクション名 の形式になる。
#   特定の習慣（:id）に対する操作なので member が適切。
#   collection は /habits/アクション名（:id なし）のため不適切。
#
# 【ai_edit に GET を使う理由】
#   ai_edit はフォームを「表示する」だけ（データを読む）→ GET
#
# 【ai_update に PATCH を使う理由】
#   ai_update は既存レコードの「部分更新」→ PATCH（REST 準拠）

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

  # ──────────────────────────────────────────────────────────────────────────
  # D-7 追加: オンボーディングルーティング
  # ──────────────────────────────────────────────────────────────────────────
  scope "/onboarding", controller: :onboardings do
    get  "step5",    action: :step5,    as: :onboarding_step5
    post "complete", action: :complete, as: :onboarding_complete
    post "skip",     action: :skip,     as: :onboarding_skip
  end
  # ──────────────────────────────────────────────────────────────────────────

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

  # ============================================================
  # D-8 変更: habits の member に ai_edit / ai_update を追加
  # ============================================================
  resources :habits, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    collection do
      get   :archived
      patch :sort
    end

    member do
      post  :archive
      patch :unarchive
      # ── D-8 追加 ────────────────────────────────────────────
      # ai_edit:
      #   GET /habits/:id/ai_edit → habits#ai_edit
      #   AI提案モーダルの「✏️ 編集する」リンクの遷移先。
      #   session に ai_context フラグを立てて編集フォームを表示する。
      #   ルートヘルパー: ai_edit_habit_path(@habit)
      #
      # ai_update:
      #   PATCH /habits/:id/ai_update → habits#ai_update
      #   ai_edit フォームの送信先。
      #   session のフラグを検証してから保存する。
      #   ルートヘルパー: ai_update_habit_path(@habit)
      get   :ai_edit
      patch :ai_update
      # ────────────────────────────────────────────────────────
    end

    resources :habit_records, only: [ :create, :update ]
  end

  resources :weekly_reflections, only: [:index, :new, :create, :show] do
    collection do
      post :complete_without_ai
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