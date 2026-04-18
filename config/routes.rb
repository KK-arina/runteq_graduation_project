# config/routes.rb
#
# ==============================================================================
# ルーティング設定（C-7 変更: ai_edit / ai_update を追加）
# ==============================================================================
#
# 【C-7 での変更点】
#   resources :tasks の member ブロックに以下を追加した。
#
#   get  :ai_edit   → GET  /tasks/:id/ai_edit
#     AI提案モーダルから「編集」リンクをクリックしたときに表示する画面。
#     通常の edit（PATCH /tasks/:id）とは別ルートにする理由:
#       ① 通常の edit はロック中でも使えてしまう（将来実装時に混乱を防ぐ）
#       ② ai_context フラグ（session）で「AI提案モーダル経由かどうか」を判定するため
#          専用のアクションを持つほうが意図が明確になる
#       ③ E-3（AI提案モーダル）実装後に、ここに遷移させるリンクを追加しやすくなる
#
#   patch :ai_update → PATCH /tasks/:id/ai_update
#     ai_edit フォームの送信先。
#     通常の update（PATCH /tasks/:id）は将来 E-3 のAI確定処理専用にする可能性があるため
#     ai_edit → ai_update という独立したペアにする。
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
  # resources :tasks
  # ---------------------------------------------------------------
  # 【C-7 変更点】
  #   member ブロックに ai_edit と ai_update を追加した。
  #
  #   member とは:
  #     特定の1件のリソースに対して操作するルートを定義するブロック。
  #     /tasks/:id/ai_edit のように :id を含むURLが生成される。
  #
  #   collection（既存）との違い:
  #     member → /tasks/:id/xxx（特定1件に対する操作）
  #     collection → /tasks/xxx（複数件や全体に対する操作）
  #
  #   生成されるルートと named path helper:
  #     GET   /tasks/:id/ai_edit   → tasks#ai_edit
  #       named helper: ai_edit_task_path(task)
  #     PATCH /tasks/:id/ai_update → tasks#ai_update
  #       named helper: ai_update_task_path(task)
  resources :tasks, only: [ :index, :new, :create, :destroy ] do
    member do
      # PATCH /tasks/:id/toggle_complete → タスクの完了↔未完了を切り替える
      patch :toggle_complete

      # PATCH /tasks/:id/archive → 完了タスクを個別にアーカイブする
      patch :archive

      # --------------------------------------------------------
      # C-7 追加: AI提案モーダル経由のタスク編集ルート
      # --------------------------------------------------------
      # GET  /tasks/:id/ai_edit   → AI専用タスク編集フォームを表示する
      # PATCH /tasks/:id/ai_update → AI専用タスク編集フォームの保存処理
      #
      # 【なぜ通常の edit / update と分けるのか】
      #   通常の edit / update は C-5 で実装した「ユーザーが直接編集する」用途。
      #   ai_edit / ai_update は「AI提案モーダル経由でのみ編集できる」用途。
      #   session に ai_context フラグを設定することで、
      #   モーダル経由以外からのアクセスを 403 で弾く。
      get   :ai_edit
      patch :ai_update
    end

    collection do
      # PATCH /tasks/archive_all_done → 完了タスクを一括アーカイブする
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