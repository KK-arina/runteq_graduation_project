# ==========================================================
# ルーティング設定
# URLとコントローラーのアクションをマッピングする
# 例: GET /users/new → UsersController#new
# ==========================================================
Rails.application.routes.draw do

  # ==========================================================
  # ヘルスチェック
  # Renderなどのホスティングサービスが稼働確認に使用
  # GET /up → 200 OK
  # ==========================================================
  get "up" => "rails/health#show", as: :rails_health_check


  # ==========================================================
  # PWA関連（現在は未使用）
  # 将来的にPWA化する場合に使用
  # ==========================================================
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest


  # ==========================================================
  # TOPページ
  # root（/）にアクセスしたときの処理
  # PagesController#index を実行
  # ==========================================================
  root "pages#index"


  # ==========================================================
  # ユーザー登録
  # RESTfulルーティング（new / create のみ有効）
  #
  # 生成されるルート:
  # GET  /users/new → users#new
  # POST /users     → users#create
  #
  # 生成されるヘルパー:
  # new_user_path
  # users_path
  # ==========================================================
  resources :users, only: [:new, :create]


  # ==========================================================
  # ログイン・ログアウト（セッション管理）
  #
  # なぜ resources を使わない？
  # - セッションは「リソース」ではなく「状態」
  # - 必要なのは new, create, destroy のみ
  # ==========================================================

  # --------------------------
  # ログインフォーム表示
  # GET /login → sessions#new
  # login_path が使用可能
  # --------------------------
  get "login", to: "sessions#new", as: :login

  # --------------------------
  # ログイン処理
  # POST /login → sessions#create
  # form_with url: login_path
  # --------------------------
  post "login", to: "sessions#create"

  # --------------------------
  # ログアウト処理
  # DELETE /logout → sessions#destroy
  # logout_path が使用可能
  # button_to "ログアウト", logout_path, method: :delete
  # --------------------------
  delete "logout", to: "sessions#destroy", as: :logout

end