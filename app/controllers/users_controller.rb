# app/controllers/users_controller.rb
#
# ==================== UsersController ====================
# このコントローラーは、ユーザー登録に関する処理を担当します
#
# アクション:
# - new: 新規登録フォームを表示
# - create: ユーザーを作成してデータベースに保存
#
# 【F-3 での変更内容】
#   user_params に :terms_agreed を追加。
#   チェックボックスの値（"1" または "0"）を Strong Parameters で受け取る。

class UsersController < ApplicationController
  # ==================== 新規登録フォーム表示 ====================
  # GET /users/new
  def new
    # User.new: 空のUserオブジェクトを作成（まだDBには保存されていない）
    # フォームに渡すことで、form_withヘルパーが適切なHTMLを生成する
    @user = User.new
  end

  # ==================== ユーザー作成処理 ====================
  # POST /users
  def create
    # user_params: Strong Parameters で許可されたパラメータのみを取得（セキュリティ対策）
    @user = User.new(user_params)

    if @user.save
      # ==================== 保存成功時の処理 ====================

      # session[:user_id]: ブラウザの暗号化 Cookie にユーザーIDを保存してログイン状態にする
      session[:user_id] = @user.id

      # 登録完了後は直接ダッシュボードへ（オンボーディングは require_login で制御）
      redirect_to dashboard_path, notice: "ユーザー登録が完了しました"
    else
      # ==================== 保存失敗時の処理 ====================

      # flash.now: render の場合に使う（リダイレクトしないので通常の flash だと次ページまで残る）
      flash.now[:alert] = "ユーザー登録に失敗しました"

      # status: :unprocessable_entity → HTTP 422（Rails 7 / Turbo で必須）
      render :new, status: :unprocessable_entity
    end
  end

  private

  # ==================== Strong Parameters ====================
  # 許可するパラメータを明示的に指定する（ホワイトリスト方式）。
  # 想定外のパラメータ（admin: true など）の書き換え攻撃を防ぐ。
  #
  # 【F-3 追加】:terms_agreed を追加。
  #   チェックボックスの値（"1" = チェックあり / "0" = チェックなし）を受け取る。
  #   User モデルの attr_accessor :terms_agreed にセットされ、
  #   :acceptance バリデーションで「同意済みか」が検証される。
  #   ここに追加しないと terms_agreed が常に nil になりバリデーションが機能しない。
  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation,
                                 :terms_agreed)
  end
end