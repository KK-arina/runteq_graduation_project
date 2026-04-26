# config/routes.rb
#
# ==============================================================================
# ルーティング定義
# ==============================================================================
#
# 【D-3 変更点】
#   resource :user_purpose のブロック内に以下を追加:
#     get  :ai_result        → 18番（AI分析結果ページ）への遷移
#     post :apply_proposals  → チェックした提案を習慣・タスクとして登録する
#
# 【なぜ on: :member を使うのか】
#   resource（単数形）の member は /user_purpose/:action の形になる。
#   例: GET  /user_purpose/ai_result        → user_purposes#ai_result
#       POST /user_purpose/apply_proposals  → user_purposes#apply_proposals
#   ※ 単数形リソースなので :id は含まれない。
# ==============================================================================

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
  # resource :user_purpose（単数形リソース）
  # ---------------------------------------------------------------
  # 【resource（単数形）と resources（複数形）の違い】
  #   resources :user_purposes → /user_purposes/:id のように id が URL に入る
  #   resource  :user_purpose  → /user_purpose のように id なしでアクセスできる
  #
  # 【なぜ単数形を使うのか】
  #   ユーザーが「自分の目標」を見る・編集するとき、
  #   自分の目標は常に1つ（is_active=true が1件）なので
  #   /user_purpose で「自分の目標」と自明になる。
  #   /user_purposes/3 のように id を指定させる必要がない。
  #
  # 【D-3 追加アクション】
  #   ai_result       : 18番 AI分析結果ページを表示する（GET）
  #   apply_proposals : チェックした提案を習慣・タスクとして登録する（POST）
  resource :user_purpose, only: [:show, :new, :create, :edit, :update] do
    member do
      # retry_analysis: 失敗した AI 分析を再実行する（D-2 実装済み）
      post :retry_analysis

      # ── D-3 追加 ──────────────────────────────────────────────
      # ai_result: 18番 AI分析結果ページ
      #   GET リクエストで閲覧専用ページを表示する。
      #   ルートヘルパー: ai_result_user_purpose_path
      get :ai_result

      # apply_proposals: チェックした提案を習慣・タスクとして登録する
      #   POST リクエストでデータ変更を伴う操作を行う。
      #   ルートヘルパー: apply_proposals_user_purpose_path
      post :apply_proposals
      # ──────────────────────────────────────────────────────────
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