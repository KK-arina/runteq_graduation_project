# test/integration/error_cases_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# Issue #30: 統合テスト（主要フロー）
# 【テスト対象】エラーケースのテスト
#
# 【このファイルがカバーする範囲】
#   - 存在しないリソースへのアクセス（404 エラー）
#   - 他ユーザーのリソースへのアクセス（認可エラー）
#   - バリデーションエラー時の挙動
#   - 未ログイン時の各操作ブロック
#
# 【なぜエラーケースのテストが重要か？】
#   正常系だけでなく異常系（エラーケース）をテストすることで、
#   ① セキュリティホール（他人のデータを操作できてしまうなど）の検出
#   ② 適切なエラーメッセージ・リダイレクトの確認
#   ③ アプリが予期しないクラッシュをしないことの保証
#   が可能になります。
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class ErrorCasesTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回自動的に呼ばれる準備処理
  # ============================================================
  setup do
    @user        = users(:one)
    @other_user  = users(:two)
    @habit       = habits(:habit_one)   # users(:one) の習慣
    @other_habit = habits(:habit_two)   # users(:two) の習慣
  end

  # ============================================================
  # テスト1: 存在しない習慣へのアクセス → 習慣一覧にリダイレクト
  # ============================================================
  # 【なぜこのテストが必要か？】
  # HabitsController#set_habit では current_user.habits.active.find(params[:id]) を使います。
  # 存在しない ID や他ユーザーの習慣 ID を指定された場合、
  # ActiveRecord::RecordNotFound が発生します。
  # rescue ブロックで flash[:alert] をセットして habits_path にリダイレクトします。
  test "存在しない習慣を削除しようとすると習慣一覧にリダイレクトされること" do
    log_in_as(@user)

    # 存在しない ID（99999）に DELETE リクエストを送ります
    # assert_no_difference: Habit のレコード数が変わらないことを確認します
    assert_no_difference("Habit.count") do
      delete habit_path(99999)
    end

    # HabitsController#set_habit の rescue ブロックが動作して habits_path にリダイレクト
    assert_redirected_to habits_path

    follow_redirect!
    # エラーメッセージが表示されること
    assert_select "div", text: /習慣が見つかりませんでした/
  end

  # ============================================================
  # テスト2: 他ユーザーの習慣にアクセスしようとすると弾かれること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # set_habit では current_user.habits.active.find を使うため、
  # 他ユーザーの習慣 ID を指定しても ActiveRecord::RecordNotFound になります。
  # これがセキュリティ上の重要な保証です。
  test "他ユーザーの習慣を削除しようとすると弾かれること" do
    log_in_as(@user)

    # 他ユーザーの習慣の件数は変わらないこと
    assert_no_difference("@other_user.habits.active.count") do
      delete habit_path(@other_habit)  # users(:two) の習慣に DELETE リクエスト
    end

    assert_redirected_to habits_path
    follow_redirect!
    assert_select "div", text: /習慣が見つかりませんでした/
  end

  # ============================================================
  # テスト3: 他ユーザーの習慣記録を更新できないこと
  # ============================================================
  # 【なぜこのテストが必要か？】
  # HabitRecordsController では set_habit で
  # current_user.habits.active.find を使って @habit を取得します。
  # 他ユーザーの習慣に紐づく記録の場合、@habit の取得時点で 404 になります。
  test "他ユーザーの習慣への記録作成は404になること" do
    log_in_as(@user)

    # users(:two) の習慣（@other_habit）に対してレコード作成を試みます
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(@other_habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # HabitRecordsController#set_habit の rescue が 404 を返すこと
    # head :not_found はボディなしで HTTP 404 を返します
    assert_response :not_found
  end

  # ============================================================
  # テスト4: 存在しない週次振り返りへのアクセス → 振り返り一覧にリダイレクト
  # ============================================================
  # 【なぜこのテストが必要か？】
  # WeeklyReflectionsController#set_weekly_reflection では
  # current_user.weekly_reflections.find(params[:id]) を使います。
  # 存在しない ID や他ユーザーの振り返り ID の場合、
  # rescue ブロックが動作して weekly_reflections_path にリダイレクトします。
  test "存在しない振り返りの詳細ページにアクセスするとリダイレクトされること" do
    log_in_as(@user)

    # 存在しない ID（99999）に GET リクエストを送ります
    get weekly_reflection_path(99999)

    # set_weekly_reflection の rescue で weekly_reflections_path にリダイレクト
    assert_redirected_to weekly_reflections_path
  end

  # ============================================================
  # テスト5: 他ユーザーの振り返り詳細ページへのアクセスを弾くこと
  # ============================================================
  # 【なぜこのテストが必要か？】
  # current_user.weekly_reflections.find を使うため、
  # 他ユーザーの振り返り ID を指定しても自分のデータから検索します。
  # 結果として「見つからない（RecordNotFound）」→ リダイレクトになります。
  test "他ユーザーの振り返りの詳細ページにアクセスできないこと" do
    log_in_as(@user)

    # users(:two) の振り返りを取得します
    other_reflection = weekly_reflections(:two_habit_one)

    # users(:one) としてログインした状態で users(:two) の振り返り詳細にアクセス
    get weekly_reflection_path(other_reflection)

    # current_user（users(:one)）の振り返りにはないため RecordNotFound → リダイレクト
    assert_redirected_to weekly_reflections_path
  end

  # ============================================================
  # テスト6: 習慣作成のバリデーションエラー時に 422 が返ること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # Rails 7 / Turbo Drive ではフォームのバリデーションエラー時に
  # 必ず HTTP 422 (Unprocessable Entity) を返す必要があります。
  # 200 を返すと Turbo がフォームエラーを正しく処理できません。
  test "習慣名が空欄の場合は 422 でエラーが表示されること" do
    log_in_as(@user)

    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name:          "",    # 空欄 → Habit モデルの validates :name, presence: true に違反
          weekly_target: 7
        }
      }
    end

    # HabitsController#create は save 失敗時に render :new, status: :unprocessable_entity を返す
    assert_response :unprocessable_entity

    # エラーメッセージのボックスが表示されること
    # bg-red-50 は Tailwind CSS のクラス名（エラーボックスのスタイル）
    assert_select "div.bg-red-50"
  end

  # ============================================================
  # テスト7: 週次目標値が範囲外の場合は 422 が返ること
  # ============================================================
  test "週次目標値が 0 の場合は 422 でエラーが表示されること" do
    log_in_as(@user)

    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name:          "テスト習慣",
          weekly_target: 0  # 0 → Habit モデルの greater_than_or_equal_to: 1 に違反
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "div.bg-red-50"
  end

  # ============================================================
  # テスト8: ユーザー登録のバリデーションエラー時に 422 が返ること
  # ============================================================
  # 【パスワード不一致の場合】
  # has_secure_password が自動生成する :password_confirmation バリデーションが
  # password と password_confirmation の一致を確認します。
  test "パスワードと確認用パスワードが一致しない場合は 422 が返ること" do
    assert_no_difference("User.count") do
      post users_path, params: {
        user: {
          name:                  "テストユーザー",
          email:                 "test_mismatch@example.com",
          password:              "password123",
          password_confirmation: "different_password"  # 意図的に不一致にする
        }
      }
    end

    # UsersController#create は save 失敗時に render :new, status: :unprocessable_entity
    assert_response :unprocessable_entity

    # 【レビュー反映 ⑤】ステータスだけでなくビューの表示も確認します
    # HTTPステータスが 422 でも、ビューが壊れてエラーが表示されていない場合は
    # テストをパスしてしまいます。assert_select でビューの描画まで検証します。
    # UsersController#create はエラー時に render :new を返すため
    # 登録フォームのページ（users/new.html.erb）がレンダリングされているはずです
    assert_select "form"  # 登録フォームが再表示されていること
  end

  # ============================================================
  # テスト9: 振り返りコメントが 1001 文字以上の場合は 422 が返ること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # WeeklyReflection モデルの validates :reflection_comment, length: { maximum: 1000 } の
  # バリデーションが正しく機能しているかを確認します。
  test "振り返りコメントが 1001 文字以上の場合は 422 が返ること" do
    # 2026-03-15（日曜）に固定します（fixtures と重複しない週）
    travel_to Time.zone.local(2026, 3, 15, 5, 0, 0) do
      log_in_as(@user)

      assert_no_difference("WeeklyReflection.count") do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment: "あ" * 1001  # 1001文字（上限 1000 文字を超える）
          }
        }
      end

      # WeeklyReflectionsController#create の rescue ブロックが動作し
      # render :new, status: :unprocessable_entity を返すこと
      assert_response :unprocessable_entity

      # 【レビュー反映 ⑤】ステータスだけでなくビューの表示も確認します
      # rescue ブロックは render :new を呼ぶため、
      # 振り返り入力フォームのページが再表示されているはずです
      assert_select "form"  # 振り返りフォームが再表示されていること
    end
  end

  # ============================================================
  # テスト10: 別の習慣のrecord_idを指定してPATCHしても404になること（Issue #41 追加）
  # ============================================================
  #
  # 【なぜこのテストが必要か？】
  # HabitRecordsController#update に追加したクロス習慣アクセス検証の動作確認。
  # URLの :habit_id と @habit_record.habit_id が不一致のとき 404 が返ることを確認する。
  #
  # 【レビュー反映: fixture不整合の修正】
  # 修正前:
  #   HabitRecord.create!(user: @user, habit: @other_habit, ...)
  #   → @other_habit は users(:two) の習慣のため、
  #     habit.user_id（users(:two).id）と record.user_id（users(:one).id）が
  #     一致しない。DBの外部キー整合性が崩れる可能性がある。
  #
  # 修正後:
  #   @user 自身が所有する「別の習慣」を新規作成してテストに使う。
  #   これにより habit.user_id と record.user_id が同一ユーザーになり、
  #   DB整合性を保ちながら「同一ユーザーの別習慣へのクロスアクセス」を正確に再現できる。
  test "別の習慣のrecord_idを指定してPATCHしても404になること" do
    travel_to Time.zone.local(2026, 3, 11, 10, 0, 0) do
      log_in_as(@user)

      # 【修正点】@user 自身が持つ「別の習慣」を新規作成する。
      # @other_habit（users(:two) の習慣）をそのまま使うと、
      # habit の所有者が users(:two) なのに記録の user が users(:one) になり、
      # DB整合性が崩れるためテストデータとして不適切。
      # Habit.create! で @user に紐づいた習慣を別途作成することで
      # 「同一ユーザーが複数の習慣を持つ」という自然なシナリオで
      # クロスアクセスを再現できる。
      another_habit = Habit.create!(
        user:          @user,    # @user（users(:one)）自身の習慣として作成
        name:          "クロスアクセステスト用習慣",
        weekly_target: 3
      )

      # another_habit に属する今日の記録を作成する（クロスアクセスの対象）。
      # user: @user, habit: another_habit → 整合性が保たれている。
      record_for_another_habit = HabitRecord.create!(
        user:        @user,
        habit:       another_habit,
        record_date: HabitRecord.today_for_record,
        completed:   false
      )

      # 攻撃シミュレーション:
      # 「@habit（習慣Aの URL）」に「another_habit のレコードID」を指定して PATCH する。
      # URL: PATCH /habits/:habit_id/habit_records/:id
      #   :habit_id = @habit.id        （habits(:habit_one) の習慣）
      #   :id       = record_for_another_habit.id（別の習慣 another_habit のレコード）
      patch habit_habit_record_path(@habit, record_for_another_habit),
            params:  { completed: "1" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # habit_records_controller.rb の unless @habit_record.habit_id == @habit.id
      # の検証により 404 が返ることを確認する。
      assert_response :not_found

      # レコードの completed が false のまま（書き換えられていない）ことを確認する。
      record_for_another_habit.reload
      assert_not record_for_another_habit.completed,
        "クロス習慣アクセスによって別習慣のレコードが更新されていないこと"
    end
  end
end
