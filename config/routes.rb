# ルーティング設定
# URLとコントローラー・アクションの対応を定義するファイル
Rails.application.routes.draw do
  # ルートパス（http://localhost:3000/）の設定
  # root: アプリケーションのトップページ（/）を指定
  # 'pages#index': PagesControllerのindexアクションを実行
  # つまり、ユーザーが http://localhost:3000/ にアクセスすると、
  # PagesController#index が実行され、app/views/pages/index.html.erb が表示される
  root 'pages#index'
  
  # ヘルスチェック用エンドポイント（Railsデフォルト）
  # Renderなどのホスティングサービスがアプリの稼働状況を確認するために使用
  # 削除しないこと
  get "up" => "rails/health#show", as: :rails_health_check
end
