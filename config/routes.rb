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
  # PagesController のアクション名は index（top ではない）
  # root "pages#top" にすると404になるため pages#index が正しい
  root "pages#index"

  # ---------------------------------------------------------------
  # resources :users, only: [:new, :create]
  # ---------------------------------------------------------------
  resources :users, only: [:new, :create]

  # ---------------------------------------------------------------
  # resource :session
  #
  # 生成されるパスヘルパー：
  #   new_session_path → GET    /session/new  ログインフォーム
  #   session_path     → POST   /session      ログイン処理
  #   session_path     → DELETE /session      ログアウト処理
  # ---------------------------------------------------------------
  resource :session, only: [:new, :create, :destroy]

  # ---------------------------------------------------------------
  # login_path / logout_path エイリアス
  #
  # 【なぜ必要か】
  #   app/controllers/application_controller.rb が redirect_to login_path を使用。
  #   app/views/shared/_header.html.erb が login_path / logout_path を使用。
  #   test/test_helper.rb の log_in_as が post login_path を使用。
  #
  # 【重要】post login_path が機能するには POST を受け付けるルートが必要。
  #   get  "/login" だけでは POST できないため、
  #   post "/login" も追加して sessions#create に向ける。
  #   これにより test_helper.rb の「post login_path」が正しく動作する。
  # ---------------------------------------------------------------
  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"          # test_helper.rb の post login_path 用
  delete "/logout", to: "sessions#destroy", as: :logout

  # ---------------------------------------------------------------
  # get "dashboard"
  # ---------------------------------------------------------------
  get "dashboard", to: "dashboards#index", as: :dashboard

  # ---------------------------------------------------------------
  # resources :habits
  #
  # member do ~ end:
  #   /habits/:id/toggle_record のような「特定IDへの操作」を定義する。
  #
  # habit_records のネストルートについて：
  #   テスト（habit_daily_record_test.rb 等）が
  #   habit_habit_records_path(@habit) / habit_habit_record_path(@habit, @record)
  #   を使用している。
  #   これは resources :habits の中に resources :habit_records を
  #   ネストすることで生成されるパスヘルパー。
  #   ただしアプリ本体は toggle_record を使う設計のため、
  #   only: [] で実際のアクションは生成せず、パスヘルパーだけ使える状態にする。
  #
  #   生成されるパスヘルパー：
  #     habit_habit_records_path(@habit)         → /habits/:habit_id/habit_records
  #     habit_habit_record_path(@habit, @record) → /habits/:habit_id/habit_records/:id
  # ---------------------------------------------------------------
  resources :habits, only: [:index, :new, :create, :destroy] do
    member do
      # PATCH /habits/:id/toggle_record
      # Hotwire によるチェックボックス即時保存エンドポイント
      patch :toggle_record
    end

    # habit_habit_records_path / habit_habit_record_path を生成するためのネスト
    # only: [] でアクションは生成しない（パスヘルパーのみ必要）
    resources :habit_records, only: [:create, :update]
  end

  # ---------------------------------------------------------------
  # resources :weekly_reflections ← Issue #23 で show を追加
  #
  #   index  → GET  /weekly_reflections          一覧ページ
  #   new    → GET  /weekly_reflections/new       入力フォームページ
  #   create → POST /weekly_reflections           保存処理
  #   show   → GET  /weekly_reflections/:id       詳細ページ
  # ---------------------------------------------------------------
  resources :weekly_reflections, only: [:index, :new, :create, :show]
end
