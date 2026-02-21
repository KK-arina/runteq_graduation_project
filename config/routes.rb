# config/routes.rb

Rails.application.routes.draw do
  # ===================================================
  # ルーティング設定
  # ===================================================
  # root: アプリのトップページ（/）にアクセスした時に
  # PagesController の index アクションを呼び出す
  root "pages#index"

  # ユーザー登録（new: 登録フォーム表示、create: 登録処理）
  resources :users, only: [:new, :create]

  # ログイン（GET: フォーム表示、POST: 認証処理）
  get  "login",  to: "sessions#new",     as: :login
  post "login",  to: "sessions#create"
  # ログアウト（DELETE: セッション削除）
  delete "logout", to: "sessions#destroy", as: :logout

  # ダッシュボード（ログイン後のホーム画面）
  get "dashboard", to: "dashboards#index", as: :dashboard

  # 習慣管理
  # do...end ブロック内にネストすることで
  # /habits/:habit_id/habit_records のようなURLを生成します
  resources :habits, only: [:index, :new, :create, :destroy] do
    resources :habit_records, only: [:create, :update]
  end

  # ===================================================
  # 週次振り返り（Issue #21 で追加）
  # ===================================================
  # resources :weekly_reflections を追加します
  # index:  一覧ページ  GET /weekly_reflections
  # new:    新規作成フォーム GET /weekly_reflections/new  ← Issue #22 で実装
  # create: 保存処理    POST /weekly_reflections        ← Issue #22 で実装
  # show:   詳細ページ  GET /weekly_reflections/:id     ← Issue #23 で実装
  #
  # only: で必要なアクションだけを定義することで、
  # 不要なルートが生成されるのを防ぎ、セキュリティを向上させます
  resources :weekly_reflections, only: [:index, :new, :create, :show]
end