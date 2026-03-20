# config/routes.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   URLとコントローラーのアクションの対応関係（ルーティング）を定義する。
#   HTTPリクエストが届いたとき、Railsはこのファイルを見て
#   「どのコントローラーのどのアクションを呼び出すか」を決定する。
# ═══════════════════════════════════════════════════════════════════

Rails.application.routes.draw do
  # ---------------------------------------------------------------
  # root
  # ---------------------------------------------------------------
  root "pages#index"

  # ---------------------------------------------------------------
  # Issue #27: カスタムエラーページ確認用ルート（開発環境のみ）
  # ---------------------------------------------------------------
  # Rails.env.development? を使うことで、このブロック内の設定は
  # 開発者のローカル環境だけで有効になる。
  #
  # 【なぜ本番環境で無効にするのか】
  #   本番環境（Render）でこのURLが有効なままだと、
  #   ① 誰でも /errors/404 にアクセスでき、意図しない挙動を生む可能性がある
  #   ② 検索エンジンがエラーページをインデックスしてしまう（SEOノイズ）
  #   ③ セキュリティスキャンツールに不要な口を晒すことになる
  #   これを if Rails.env.development? で囲むだけで上記を防げる。
  if Rails.env.development?
    scope "/errors" do
      # get "/URL", to: "コントローラー名#アクション名", as: :パスヘルパー名
      get "/404", to: "pages#error_404", as: :error_404
      get "/422", to: "pages#error_422", as: :error_422
      get "/500", to: "pages#error_500", as: :error_500
    end
  end

  # ---------------------------------------------------------------
  # resources :users, only: [:new, :create]
  # ---------------------------------------------------------------
  resources :users, only: [ :new, :create ]

  # ---------------------------------------------------------------
  # resource :session
  # ---------------------------------------------------------------
  resource :session, only: [ :new, :create, :destroy ]

  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # ---------------------------------------------------------------
  # get "dashboard"
  # ---------------------------------------------------------------
  get "dashboard", to: "dashboards#index", as: :dashboard

  # ---------------------------------------------------------------
  # resources :habits
  # ---------------------------------------------------------------
  resources :habits, only: [ :index, :new, :create, :destroy ] do
    member do
      patch :toggle_record
    end
    resources :habit_records, only: [ :create, :update ]
  end

  # ---------------------------------------------------------------
  # resources :weekly_reflections
  # ---------------------------------------------------------------
  resources :weekly_reflections, only: [ :index, :new, :create, :show ]

  # ---------------------------------------------------------------
  # Issue #27: catch-all ルート（必ず最後に記述する）
  # ---------------------------------------------------------------
  # どのルートにもマッチしなかったURLを ErrorsController#not_found に向ける。
  #
  # 【なぜ application#render_404 ではダメなのか】
  #   render_404 は ApplicationController の private メソッドのため、
  #   ルーティングからアクションとして直接呼び出せない。
  #   public アクションを持つ ErrorsController を経由する必要がある。
  #
  # via: :all → GET / POST / DELETE など全HTTPメソッドに対応する。
  # 必ず最後に書くこと（先に書くとすべてのURLが404になる）。
  match "*path", to: "errors#not_found", via: :all
end
