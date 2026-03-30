# test/controllers/habits_menu_controller_test.rb
#
# ==============================================================================
# HabitsController の削除確認モーダル（M-1）テスト（B-5 修正版）
# ==============================================================================
# 【このファイルの役割】
#   B-5 で追加・変更した内容が正しく動作するかを検証する。
#
# 【B-5 修正版での変更内容】
#   パーシャルの構造変更に合わせてテストを更新した。
#
#   【変更前】
#     data-controller="habit-menu" の DIV に以下の属性があった:
#       data-habit-menu-archive-url-value
#       data-habit-menu-destroy-url-value
#
#   【変更後】
#     data-controller="habit-menu" の DIV には以下の属性がある:
#       data-habit-menu-modal-id-value  （モーダルのDOM IDを渡す）
#       data-habit-menu-sheet-id-value  （ボトムシートのDOM IDを渡す）
#     アーカイブ・削除のURLは button_to の action 属性として
#     モーダル・ボトムシートのパネル内に直接記載される。
#
# 【Stimulus の動作はテストできない理由】
#   Stimulus の動作（モーダルの表示/非表示）は JavaScript の世界のため、
#   Rails の統合テスト（ActionDispatch::IntegrationTest）では検証できない。
#   JS の動作確認は手動テスト（ブラウザ確認）で行う。
# ==============================================================================

require "test_helper"

class HabitsMenuControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:one)

    # テスト用アクティブ習慣を作成する
    @habit = @user.habits.create!(
      name:             "⋯メニューテスト習慣",
      measurement_type: :check_type,
      weekly_target:    5
    )

    # ログインする
    # 【注意】SessionsController は params[:session][:email] で受け取るため
    # session: {} キーが必要。忘れると NoMethodError になる。
    post login_path, params: {
      session: { email: @user.email, password: "password" }
    }
  end

  # ============================================================
  # GET /habits（一覧ページ）の HTML 構造確認
  # ============================================================

  test "習慣一覧ページに data-controller='habit-menu' が含まれる（ロック解除中）" do
    get habits_path
    assert_response :success

    # data-controller="habit-menu" を持つ要素が1つ以上存在することを確認する
    # ロック解除中（前週の振り返りレコードなし = 初週）なのでボタンが表示されるはず
    assert_select "[data-controller='habit-menu']"
  end

  test "習慣一覧ページに data-habit-menu-habit-name-value が含まれる" do
    get habits_path
    assert_response :success

    # 習慣名が data-habit-menu-habit-name-value 属性に含まれることを確認する
    assert_select "[data-habit-menu-habit-name-value='⋯メニューテスト習慣']"
  end

  test "習慣一覧ページに data-habit-menu-modal-id-value が含まれる" do
    get habits_path
    assert_response :success

    # 【修正前】data-habit-menu-archive-url-value を確認していた
    # 【修正後】モーダルIDを渡す data-habit-menu-modal-id-value を確認する
    # 理由: パーシャル修正でアーカイブURLは button_to の action として
    #       モーダルパネル内に直接記載されるように変わった。
    #       data-controller DIV が持つ属性も変わったためテストを更新する。
    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']"
  end

  test "習慣一覧ページに data-habit-menu-sheet-id-value が含まれる" do
    get habits_path
    assert_response :success

    # 【修正前】data-habit-menu-destroy-url-value を確認していた
    # 【修正後】ボトムシートIDを渡す data-habit-menu-sheet-id-value を確認する
    assert_select "[data-habit-menu-sheet-id-value='habit-sheet-#{@habit.id}']"
  end

  test "習慣一覧ページにモーダル用のDIVが含まれる" do
    get habits_path
    assert_response :success

    # デスクトップ用モーダルが正しいIDで生成されていることを確認する
    # id="habit-modal-{habit.id}" の div が存在するはず
    assert_select "#habit-modal-#{@habit.id}"
  end

  test "習慣一覧ページにボトムシート用のDIVが含まれる" do
    get habits_path
    assert_response :success

    # スマホ用ボトムシートが正しいIDで生成されていることを確認する
    assert_select "#habit-sheet-#{@habit.id}"
  end

  test "習慣一覧ページのモーダル内にアーカイブURLが含まれる" do
    get habits_path
    assert_response :success

    # button_to が生成する form の action 属性を確認する
    # モーダル内のアーカイブボタンが正しいURLを持つことを検証する
    assert_select "#habit-modal-#{@habit.id}" do
      assert_select "form[action='#{archive_habit_path(@habit)}']"
    end
  end

  test "習慣一覧ページのモーダル内に削除URLが含まれる" do
    get habits_path
    assert_response :success

    # button_to が生成する form の action 属性を確認する
    # モーダル内の削除ボタンが正しいURLを持つことを検証する
    assert_select "#habit-modal-#{@habit.id}" do
      assert_select "form[action='#{habit_path(@habit)}']"
    end
  end

  # ============================================================
  # ロック中の動作確認
  # ============================================================

  test "ロック中は data-controller='habit-menu' が出力されない" do
    # 前週の振り返りを「未完了」状態で作成してロック状態を作る
    # locked? メソッドは「月曜AM4:00以降 かつ 前週レコード存在 かつ 未完了」でtrueになる
    last_week_start = HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week

    @user.weekly_reflections.create!(
      week_start_date: last_week_start,
      week_end_date:   last_week_start + 6.days
      # completed_at は設定しない → 未完了状態
    )

    # 月曜AM4:00以降の時刻にトラベルしてロック状態を作る
    # beginning_of_week（月曜） + 1.week + 5.hours = 月曜 AM5:00（AM4:00以降）
    travel_to last_week_start + 1.week + 5.hours do
      get habits_path
      assert_response :success

      # ロック中は unless locked の条件が false になり
      # パーシャル全体が出力されないため data-controller="habit-menu" は存在しない
      assert_select "[data-controller='habit-menu']", count: 0
    end
  end

  # ============================================================
  # アーカイブ・削除の動作確認（HTTPリクエストレベル）
  # ============================================================

  test "POST /habits/:id/archive でアーカイブが実行されトーストが表示される" do
    post archive_habit_path(@habit)

    # 303 See Other でリダイレクトされることを確認する
    # HabitsController#archive は redirect_to habits_path, status: :see_other を使っている
    assert_redirected_to habits_path

    # リダイレクト先にアクセスしてフラッシュメッセージを確認する
    follow_redirect!
    assert_response :success

    # flash[:notice] のメッセージがページに含まれることを確認する
    assert_match "アーカイブしました", response.body
  end

  test "DELETE /habits/:id で削除が実行されトーストが表示される" do
    delete habit_path(@habit)

    assert_redirected_to habits_path

    follow_redirect!
    assert_response :success

    assert_match "削除しました", response.body
  end

  test "アーカイブ後に習慣一覧から習慣が消える" do
    post archive_habit_path(@habit)
    follow_redirect!

    # アーカイブ後は scope :active（archived_at: nil の条件）により
    # 一覧に表示されないため data-habit-menu-modal-id-value も出力されないはず
    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']", count: 0
  end

  test "削除後に習慣一覧から習慣が消える" do
    delete habit_path(@habit)
    follow_redirect!

    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']", count: 0
  end

  test "他ユーザーの習慣はアーカイブも削除もできない" do
    other_user  = users(:two)
    other_habit = other_user.habits.create!(
      name:             "他ユーザー習慣",
      measurement_type: :check_type,
      weekly_target:    5
    )

    # 他ユーザーの習慣をアーカイブしようとする
    # set_habit が current_user.habits.where(deleted_at: nil).find(params[:id]) なので
    # RecordNotFound → habits_path へリダイレクトされるはず
    post archive_habit_path(other_habit)
    assert_redirected_to habits_path
    other_habit.reload
    assert_nil other_habit.archived_at, "他ユーザーの習慣の archived_at は変更されないべき"

    # 他ユーザーの習慣を削除しようとする
    delete habit_path(other_habit)
    assert_redirected_to habits_path
    other_habit.reload
    assert_nil other_habit.deleted_at, "他ユーザーの習慣の deleted_at は変更されないべき"
  end
end