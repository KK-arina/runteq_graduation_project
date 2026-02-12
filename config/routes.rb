# ==================== ルーティング設定 ====================
# このファイルは、URLとコントローラーのアクションをマッピングします
# 例: GET /users/new → UsersController#new

Rails.application.routes.draw do
  # ==================== ヘルスチェック ====================
  # Renderなどのホスティングサービスがアプリの稼働状況を確認するためのエンドポイント
  # GET /up → 200 OKを返す（アプリが起動していることを確認）
  get "up" => "rails/health#show", as: :rails_health_check

  # ==================== PWA関連 ====================
  # Progressive Web App用のマニフェストとサービスワーカー
  # 現在は使用していないが、将来のPWA化のために残している
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # ==================== TOPページ ====================
  # root: ルートパス（/）にアクセスした時の処理
  # pages#index: PagesControllerのindexアクションを実行
  # TOPページ（ランディングページ）を表示
  root "pages#index"
  
  # ==================== ユーザー登録 ====================
  # resources: RESTfulなルーティングを自動生成
  # only: [:new, :create]: newとcreateアクションのみ有効化
  # 
  # 自動生成されるルート:
  # GET    /users/new      → users#new    （新規登録フォーム表示）
  # POST   /users          → users#create （ユーザー作成処理）
  # 
  # 自動生成されるヘルパーメソッド:
  # new_user_path    → /users/new （リンク作成時に使用）
  # users_path       → /users      （フォーム送信先に使用）
  resources :users, only: [:new, :create]
end
