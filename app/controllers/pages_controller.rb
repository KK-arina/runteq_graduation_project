# PagesController
# 静的ページ（ランディングページなど）を表示するコントローラー
# ApplicationControllerを継承することで、Rails標準の機能（CSRF保護など）を使える
class PagesController < ApplicationController
  # indexアクション
  # ルートパス（/）にアクセスしたときに実行されるメソッド
  # 今回はデータベースから情報を取得する必要がないため、処理は空
  # Railsは自動的に app/views/pages/index.html.erb を表示する
  def index
    # 処理なし（ビューファイルを表示するだけ）
  end
end
