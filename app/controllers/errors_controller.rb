# app/controllers/errors_controller.rb
#
# 【このファイルの役割】
#   カスタムエラーページを表示する専用コントローラー。
#
# 【なぜ ApplicationController#render_404 を直接呼べないのか】
#   render_404 は ApplicationController の private メソッドとして定義している。
#   private メソッドはルーティングからアクションとして呼び出せない。
#   Rails のルーティングはコントローラーの public メソッドのみを
#   アクションとして認識するため、専用コントローラーが必要。

class ErrorsController < ApplicationController
  # not_found:
  #   catch-all ルート（match "*path"）にマッチしたとき呼ばれる。
  #   存在しないURLへのアクセス時に 404 ページを表示する。
  #   render_404 は ApplicationController に定義された private メソッドだが、
  #   継承しているため ErrorsController からは呼び出せる。
  def not_found
    render_404
  end
end