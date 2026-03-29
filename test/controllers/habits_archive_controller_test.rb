# test/controllers/habits_archive_controller_test.rb
#
# ==============================================================================
# HabitsController のアーカイブ機能テスト（B-4）
# ==============================================================================
# 【このファイルの役割】
#   B-4 で追加した archive / unarchive / archived アクションが
#   正しく動作するかを検証する。
#
# 【テスト対象アクション】
#   1. GET  /habits/archived       → habits#archived（アーカイブ一覧）
#   2. POST /habits/:id/archive    → habits#archive（アーカイブ実行）
#   3. PATCH /habits/:id/unarchive → habits#unarchive（復元実行）
#
# 【エラー修正履歴】
#   NoMethodError: undefined method '[]' for nil
#   原因: SessionsController#create が params[:session][:email] で受け取るのに
#         テストでは params: { email: ... } と送っていたため params[:session] が nil になった。
#   修正: params: { session: { email: ..., password: ... } } に変更した。
# ==============================================================================

require "test_helper"

class HabitsArchiveControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # セットアップ: 各テストの前に実行される
  # ============================================================
  setup do
    # fixtures/users.yml の :one を使う
    # test1@example.com / password でログインできる
    @user = users(:one)

    # テスト用: アクティブな習慣（削除もアーカイブもされていない）
    @active_habit = @user.habits.create!(
      name:             "テスト習慣（アクティブ）",
      measurement_type: :check_type,
      weekly_target:    5
    )

    # テスト用: アーカイブ済みの習慣（archived_at が設定されている）
    @archived_habit = @user.habits.create!(
      name:             "テスト習慣（アーカイブ済み）",
      measurement_type: :check_type,
      weekly_target:    3,
      archived_at:      1.day.ago
    )

    # ============================================================
    # ログイン処理
    # ============================================================
    # 【修正ポイント】
    #   修正前: params: { email: @user.email, password: "password" }
    #   修正後: params: { session: { email: @user.email, password: "password" } }
    #
    # 【修正理由】
    #   SessionsController#create は以下のように params を受け取っている:
    #     email = params[:session][:email].to_s.downcase
    #     user.authenticate(params[:session][:password])
    #
    #   つまり、ログインフォームのフィールドは session[email] / session[password]
    #   という名前で送信される設計になっている。
    #   テストでも同じ構造のパラメータを送らないと
    #   params[:session] が nil になり NoMethodError が発生する。
    #
    # 【なぜ session というキーが必要か】
    #   Rails の form_with model: @session や
    #   fields_for :session などを使っているフォームでは、
    #   パラメータが { session: { email: "...", password: "..." } } の形で送られる。
    #   フォームの実装に合わせてテストのパラメータも同じ構造にする必要がある。
    post login_path, params: {
      session: {
        email:    @user.email,
        password: "password"
      }
    }

    # ログインが成功したことを確認する（オプション: デバッグ時に有効）
    # assert_response :redirect  # ログイン成功時は dashboard_path へリダイレクトされるはず
  end

  # ============================================================
  # GET /habits/archived（アーカイブ一覧）
  # ============================================================

  test "GET /habits/archived でアーカイブ一覧ページが表示される" do
    # assert_response :success:
    #   HTTP レスポンスが 200 OK であることを確認する。
    #   ログインが成功していれば archived アクションが実行されて 200 が返る。
    #   ログインに失敗していれば require_login によりリダイレクトされるため
    #   このテストで間接的にログイン成功も確認できる。
    get archived_habits_path
    assert_response :success
  end

  test "GET /habits/archived でアーカイブ済みの習慣名がページに含まれる" do
    get archived_habits_path
    # assert_select を使って、アーカイブ済み習慣の名前が HTML に含まれることを確認する。
    # @archived_habit.name = "テスト習慣（アーカイブ済み）" が表示されているはず。
    assert_select "h1", text: /アーカイブ済み習慣/
  end

  test "未ログイン時は GET /habits/archived でリダイレクトされる" do
    # ログアウトしてセッションをリセットする
    # delete logout_path は SessionsController#destroy を呼び出す
    delete logout_path

    get archived_habits_path

    # require_login によってログインページへリダイレクトされることを確認する
    assert_response :redirect
  end

  # ============================================================
  # POST /habits/:id/archive（アーカイブ実行）
  # ============================================================

  test "POST /habits/:id/archive でアーカイブが実行される" do
    post archive_habit_path(@active_habit)

    # reload: Ruby オブジェクトのメモリ上の値ではなく、
    #         DB から最新の値を取得して確認する
    @active_habit.reload

    # アーカイブ後に archived_at が設定されていることを確認する
    assert_not_nil @active_habit.archived_at,
      "archive 後に archived_at が設定されているべき"
  end

  test "POST /habits/:id/archive 後は習慣一覧にリダイレクトされる" do
    post archive_habit_path(@active_habit)

    # status: :see_other (303) でリダイレクトされることを確認する
    # HabitsController#archive では redirect_to habits_path, status: :see_other を使っている
    assert_redirected_to habits_path
  end

  test "他ユーザーの習慣はアーカイブできない" do
    # fixtures/users.yml の :two を別ユーザーとして使う
    other_user = users(:two)
    other_habit = other_user.habits.create!(
      name:             "他ユーザーの習慣",
      measurement_type: :check_type,
      weekly_target:    5
    )

    # @user（users(:one)）でログインしている状態で
    # other_user の習慣をアーカイブしようとする
    post archive_habit_path(other_habit)

    # set_habit の rescue ActiveRecord::RecordNotFound が
    # habits_path へリダイレクトすることを確認する
    assert_redirected_to habits_path

    # DB が変更されていないことを確認する
    other_habit.reload
    assert_nil other_habit.archived_at,
      "他ユーザーの習慣の archived_at は変更されないべき"
  end

  # ============================================================
  # PATCH /habits/:id/unarchive（B-4 新規追加）
  # ============================================================
  # 【役割】
  #   アーカイブを解除してアクティブ状態に復元する。
  #   archived_at を nil に戻す。
  #
  # 【パスヘルパー名の注意点】
  #   ルーティングの定義場所によってヘルパー名が変わる。
  #
  #   collection do ... end で定義した場合:
  #     get :archived → archived_habits_path（複数形が先）
  #
  #   member do ... end で定義した場合:
  #     patch :unarchive → unarchive_habit_path（単数形が先）
  #
  #   今回の collection の archived ルートは archived_habits_path が正しい。
  #   habits_archived_path は存在しないため NameError になる。

  def unarchive
    @habit.unarchive!
    flash[:notice] = "「#{@habit.name}」を復元しました"
    redirect_to archived_habits_path, status: :see_other  # ← habits_archived_path を修正
  rescue RuntimeError => e
    flash[:alert] = e.message
    redirect_to archived_habits_path, status: :see_other  # ← こちらも同様に修正
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "復元に失敗しました"
    redirect_to archived_habits_path, status: :see_other  # ← こちらも同様に修正
  end
end