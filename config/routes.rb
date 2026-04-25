# config/routes.rb
# （既存内容から変更箇所のみ抜粋）
# ==============================================================================
# 変更点: D-1 追加
#   resource :user_purpose を追加する。
#   resource（単数形）を使う理由:
#     1ユーザーが持つ「現在の目標」は常に1件なので
#     /user_purposes/1 のような id を URL に含めない設計にする。
#     /user_purpose/new, /user_purpose/edit など id なしでアクセスできる。
#   only: で必要なアクションだけを定義してルーティングをシンプルに保つ。
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
  # D-1 追加: resource :user_purpose（単数形リソース）
  # ---------------------------------------------------------------
  # 【resource（単数形）vs resources（複数形）の違い】
  #   resources :user_purposes → /user_purposes/:id のように id が URL に入る
  #   resource  :user_purpose  → /user_purpose のように id なしでアクセスできる
  #
  # 【なぜ単数形を使うのか】
  #   ユーザーが「自分の目標」を見る・編集するとき、
  #   自分の目標は常に1つ（is_active=true が1件）なので
  #   /user_purpose で「自分の目標」と自明になる。
  #   /user_purposes/3 のように id を指定させる必要がない。
  #
  # 【生成されるルートと named path helper】
  #   GET  /user_purpose/new  → user_purposes#new  → new_user_purpose_path
  #   POST /user_purpose      → user_purposes#create
  #   GET  /user_purpose      → user_purposes#show  → user_purpose_path
  #   GET  /user_purpose/edit → user_purposes#edit  → edit_user_purpose_path
  #   PATCH/PUT /user_purpose → user_purposes#update
  #
  # 【注意: resource は singular resource なのでコントローラー名は複数形】
  #   Rails の慣例でコントローラーは UserPurposesController（複数形）のまま。
  resource :user_purpose, only: [:show, :new, :create, :edit, :update] do
    # retry_analysis: 失敗した AI 分析を再実行するエンドポイント
    # POST /user_purpose/retry_analysis
    # on: :member → /user_purpose/:id/retry_analysis ではなく
    #               単数形リソース（/user_purpose/retry_analysis）になる
    post :retry_analysis, on: :member
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