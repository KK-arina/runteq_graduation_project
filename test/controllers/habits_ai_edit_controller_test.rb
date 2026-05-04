# test/controllers/habits_ai_edit_controller_test.rb
#
# ==============================================================================
# HabitsController ai_edit / ai_update のコントローラーテスト（D-8）
# ==============================================================================
#
# 【このファイルの役割】
#   D-8 で追加した habits#ai_edit / habits#ai_update アクションの
#   動作を検証する。
#   C-7 の tasks_ai_edit_controller_test.rb と同じ構造で書く。
#
# 【テスト設計の方針】
#   ① 正常系: ai_edit 経由で ai_update が成功する
#   ② 不正アクセス: session フラグなしで ai_update を叩いたら弾かれる
#   ③ 他ユーザーの習慣に対してアクセスしたら習慣一覧にリダイレクトされる
#      【注意】set_habit は RecordNotFound を rescue して redirect_to habits_path
#      （302）を返す設計のため、404 ではなく 302 が正しい期待値。
#   ④ バリデーションエラー時に ai_edit を再描画する
#   ⑤ 未ログイン状態ではアクセスできない
#   ⑥ 測定タイプが変更できないこと（ai_update_params の二重防御）
# ==============================================================================

require "test_helper"

class HabitsAiEditControllerTest < ActionDispatch::IntegrationTest
  setup do
    # fixtures からテスト用ユーザーと習慣を取得する
    @user  = users(:one)
    @habit = habits(:habit_one)

    # ログイン状態を作る
    # session: { email: ..., password: ... } の入れ子構造が必要
    # （SessionsController が params[:session][:email] で取得するため）
    post login_path, params: { session: { email: @user.email, password: "password" } }

    # ログイン成功を確認する
    # 失敗すると後続テストが全て「未ログイン扱い」になるため必ず確認する
    assert_response :redirect, "ログインに失敗しています。fixtures のパスワードを確認してください"
  end

  # ============================================================
  # GET /habits/:id/ai_edit のテスト
  # ============================================================

  # テスト①: 正常系 - ai_edit ページが表示される
  test "ai_edit ページが正常に表示されること" do
    get ai_edit_habit_path(@habit)

    # HTTP 200 が返ることを確認する
    assert_response :success

    # 「AI提案モーダルから編集しています」バナーが表示されることを確認
    assert_match "AI提案モーダルから編集しています", response.body,
                 "AI経由限定バナーが表示されていません"
  end

  # テスト②: ai_edit にアクセスすると session に ai_context_habit_id がセットされる
  test "ai_edit にアクセスすると session に ai_context_habit_id がセットされること" do
    get ai_edit_habit_path(@habit)

    assert_response :success

    # session[:ai_context_habit_id] が @habit.id にセットされているか確認
    # ActionDispatch::IntegrationTest では session ヘルパーでセッションを確認できる
    assert_equal @habit.id, session[:ai_context_habit_id],
                 "session[:ai_context_habit_id] が正しくセットされていません"
  end

  # テスト③: 未ログイン状態ではログインページにリダイレクトされる
  test "未ログイン状態で ai_edit にアクセスするとログインページにリダイレクトされること" do
    delete logout_path

    get ai_edit_habit_path(@habit)

    assert_redirected_to login_path,
                         "ログインページへのリダイレクトが発生していません"
  end

  # テスト④: 他ユーザーの習慣にアクセスすると習慣一覧にリダイレクトされる
  #
  # 【なぜ 404 ではなく 302 を期待するのか】
  #   set_habit は RecordNotFound（他ユーザーの習慣は current_user からは
  #   「存在しない」と同義）を rescue して redirect_to habits_path を実行する。
  #   rescue 節が ApplicationController の rescue_from より先に動くため
  #   実際のレスポンスは 302 リダイレクトになる。
  #   flash[:alert] に「習慣が見つかりませんでした」が入ることも合わせて確認する。
  test "他ユーザーの習慣に対して ai_edit にアクセスすると習慣一覧にリダイレクトされること" do
    # habits(:habit_two) は users(:two) の習慣（fixtures で確認済み）
    other_habit = habits(:habit_two)

    get ai_edit_habit_path(other_habit)

    # set_habit の rescue → redirect_to habits_path（302）
    assert_redirected_to habits_path,
                         "他ユーザーの習慣にアクセスしたとき習慣一覧へのリダイレクトが発生していません"
  end

  # ============================================================
  # PATCH /habits/:id/ai_update のテスト
  # ============================================================

  # テスト⑤: 正常系 - ai_edit 経由で ai_update が成功する
  test "ai_edit 経由で ai_update が成功して習慣一覧にリダイレクトされること" do
    # まず ai_edit にアクセスして session にフラグを立てる
    get ai_edit_habit_path(@habit)
    assert_response :success

    # ai_update を実行する
    patch ai_update_habit_path(@habit), params: {
      habit: {
        name:          "AIが提案した新しい習慣名",
        weekly_target: 3
      }
    }

    # 習慣一覧にリダイレクトされることを確認
    assert_redirected_to habits_path,
                         "保存成功後に習慣一覧にリダイレクトされていません"

    # DB に保存されたか確認
    @habit.reload
    assert_equal "AIが提案した新しい習慣名", @habit.name,
                 "習慣名が保存されていません"
    assert_equal 3, @habit.weekly_target,
                 "週次目標値が保存されていません"
  end

  # テスト⑥: session フラグなしで ai_update を叩いたら弾かれる（不正アクセス）
  test "session フラグなしで ai_update を叩くと習慣一覧にリダイレクトされること" do
    # ai_edit を経由せず直接 ai_update を叩く
    # → session[:ai_context_habit_id] が nil なので verify_ai_context が true を返す
    patch ai_update_habit_path(@habit), params: {
      habit: { name: "不正アクセスによる変更", weekly_target: 1 }
    }

    # 習慣一覧へのリダイレクトを確認（302）
    assert_redirected_to habits_path,
                         "不正アクセスが弾かれていません"

    # DB が変更されていないことを確認
    @habit.reload
    assert_not_equal "不正アクセスによる変更", @habit.name,
                     "不正アクセスで習慣名が変更されてしまいました"
  end

  # テスト⑦: 他ユーザーの習慣に ai_update を送ると習慣一覧にリダイレクトされる
  #
  # 【なぜ 404 ではなく 302 を期待するのか】
  #   テスト④と同じ理由。set_habit の rescue が redirect_to habits_path を実行するため。
  test "他ユーザーの習慣に ai_update を送ると習慣一覧にリダイレクトされること" do
    other_habit = habits(:habit_two)

    patch ai_update_habit_path(other_habit), params: {
      habit: { name: "不正変更", weekly_target: 1 }
    }

    # set_habit の rescue → redirect_to habits_path（302）
    assert_redirected_to habits_path,
                         "他ユーザーの習慣を変更しようとしたとき習慣一覧へのリダイレクトが発生していません"
  end

  # テスト⑧: バリデーションエラー時に ai_edit を再描画する
  test "習慣名が空のとき ai_edit を再描画してエラーを表示すること" do
    # ai_edit にアクセスして session にフラグを立てる
    get ai_edit_habit_path(@habit)
    assert_response :success

    # 習慣名を空にして送信（バリデーションエラーを発生させる）
    patch ai_update_habit_path(@habit), params: {
      habit: { name: "", weekly_target: 3 }
    }

    # HTTP 422 が返ることを確認
    assert_response :unprocessable_entity,
                    "バリデーションエラー時に 422 が返っていません"

    # エラーメッセージが表示されることを確認
    assert_match "入力内容に問題があります", response.body,
                 "エラーメッセージが表示されていません"
  end

  # テスト⑨: measurement_type が変更できないこと（ai_update_params の二重防御）
  test "ai_update で measurement_type を送っても変更されないこと" do
    # @habit の現在の measurement_type を記録する
    original_type = @habit.measurement_type

    # ai_edit にアクセスして session にフラグを立てる
    get ai_edit_habit_path(@habit)

    # measurement_type を変更しようとする
    opposite_type = @habit.check_type? ? "numeric_type" : "check_type"

    patch ai_update_habit_path(@habit), params: {
      habit: {
        name:             @habit.name,
        weekly_target:    @habit.weekly_target,
        measurement_type: opposite_type
      }
    }

    # 保存成功後に DB を確認する
    @habit.reload

    # measurement_type が変わっていないことを確認
    assert_equal original_type, @habit.measurement_type,
                 "measurement_type が変更されてしまいました（ai_update_params の防御が機能していません）"
  end

  # テスト⑩: 保存成功後に session の ai_context_habit_id がクリアされる
  test "ai_update 成功後に session の ai_context_habit_id がクリアされること" do
    # ai_edit にアクセスして session にフラグを立てる
    get ai_edit_habit_path(@habit)
    assert_equal @habit.id, session[:ai_context_habit_id]

    # ai_update を実行する
    patch ai_update_habit_path(@habit), params: {
      habit: { name: @habit.name, weekly_target: @habit.weekly_target }
    }

    assert_redirected_to habits_path

    # session からフラグが削除されていることを確認
    assert_nil session[:ai_context_habit_id],
               "保存成功後も session[:ai_context_habit_id] が残っています"
  end
end