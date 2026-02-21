# config/routes.rb
# =============================================================
# Railsのルーティング設定ファイル
# 「どのURLにアクセスしたら、どのControllerのどのActionを呼ぶか」を定義する
# =============================================================

Rails.application.routes.draw do
  # ルートパス（"/"）にアクセスしたときの処理
  # ログインしていない場合はランディングページ、ログイン済みならダッシュボードへ
  # この振り分けはApplicationControllerで行う（後述）
  root "pages#index"

  # ユーザー登録（新規作成のみ許可）
  resources :users, only: [:new, :create]

  # ログイン・ログアウト（セッション管理）
  get  "login",  to: "sessions#new",     as: :login
  post "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # ダッシュボード
  # GET /dashboard でdashboards#indexを呼ぶ
  # as: :dashboard で dashboard_path というヘルパーメソッドが使えるようになる
  get "dashboard", to: "dashboards#index", as: :dashboard

  # 習慣管理
  resources :habits, only: [:index, :new, :create, :destroy] do
    # ネストされたルーティング
    # GET  /habits/:habit_id/habit_records       → habit_records#create
    # PATCH /habits/:habit_id/habit_records/:id  → habit_records#update
    resources :habit_records, only: [:create, :update]
  end
end