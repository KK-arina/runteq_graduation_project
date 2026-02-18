# ==============================================================================
# config/routes.rb
# ==============================================================================
# 【ルーティング設計の考え方】
#
#   HabitRecord は Habit に「従属する（nested）」リソースです。
#   「特定の習慣に対する記録」なので、URL に habit_id を含めます。
#
#   ネストされたルート例:
#     POST   /habits/:habit_id/habit_records        → habit_records#create
#     PATCH  /habits/:habit_id/habit_records/:id    → habit_records#update
#
#   resources ... only: で不要なアクションを生成しないようにします。
#   これにより、不要なルートへのアクセスを防ぎます（セキュリティ）。
# ==============================================================================
Rails.application.routes.draw do
  # ルートパス（トップページ）
  root "pages#index"

  # ユーザー登録
  resources :users, only: [:new, :create]

  # ログイン・ログアウト
  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # 習慣管理 + ネストした日次記録
  # shallow: false にすることで、habit_records の URL 全てに habit_id が含まれる。
  # これにより「どの習慣の記録か」が URL から明確になる。
  resources :habits, only: [:index, :new, :create, :destroy] do
    # habit_records は habits にネストする
    # only: [:create, :update] で作成・更新のみ許可する
    #   - 記録の「一覧」や「削除」は今回のMVPでは不要なため除外
    resources :habit_records, only: [:create, :update]
  end

  # ダッシュボード（Week 3で実装予定。今は空でOK）
  # get "dashboard", to: "dashboard#index", as: :dashboard
end