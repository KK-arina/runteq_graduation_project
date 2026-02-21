# config/routes.rb

Rails.application.routes.draw do
  # ==========================================
  # ルートパス（TOPページ）
  # ==========================================
  # ログイン済みの場合はダッシュボードへリダイレクト
  root "pages#index"

  # ==========================================
  # ユーザー登録
  # ==========================================
  # new  → GET  /users/new   → 登録フォーム表示
  # create → POST /users     → 登録処理
  resources :users, only: [:new, :create]

  # ==========================================
  # ログイン・ログアウト
  # ==========================================
  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # ==========================================
  # ダッシュボード
  # ==========================================
  get "dashboard", to: "dashboards#index", as: :dashboard

  # ==========================================
  # 習慣管理
  # ==========================================
  # ネスト構造:
  #   習慣記録(habit_records)は習慣(habit)に紐づく
  #   例: /habits/1/habit_records → habit_id=1 の記録を操作
  resources :habits, only: [:index, :new, :create, :destroy] do
    resources :habit_records, only: [:create, :update]
  end

  # ==========================================
  # 週次振り返り
  # ==========================================
  # index  → GET  /weekly_reflections         → 一覧
  # new    → GET  /weekly_reflections/new     → 新規作成フォーム  ← Issue #22で追加
  # create → POST /weekly_reflections         → 保存処理          ← Issue #22で追加
  # show   → GET  /weekly_reflections/:id     → 詳細              ← Issue #23で追加予定
  resources :weekly_reflections, only: [:index, :new, :create, :show]
end