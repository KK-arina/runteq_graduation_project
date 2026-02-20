# test/integration/habit_management_test.rb
# ============================================================
# Issue #17: 習慣管理機能 統合テスト
#
# 【統合テスト（Integration Test）とは？】
# ブラウザでの実際の操作フロー（HTTPリクエスト→レスポンス）を
# シミュレートするテストです。
# 単体テスト（モデルテスト）では確認できない
# 「コントローラー + モデル + ビュー」の連携を検証します。
#
# 【このファイルでテストする内容】
# - 習慣作成の正常系・異常系・セキュリティ・未ログイン
# - 習慣削除の正常系・セキュリティ・論理削除済み・未ログイン
# - 進捗率表示の確認
# ============================================================

require "test_helper"

class HabitManagementTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回呼ばれる準備処理
  # フィクスチャからテストデータを取得します
  # ============================================================
  setup do
    # users(:one) → test/fixtures/users.yml の "one" を取得
    @user        = users(:one)
    @other_user  = users(:two)
    # habits(:habit_one) → test/fixtures/habits.yml の "habit_one" を取得
    # キー名を habit_one にすることで「ユーザー1の習慣」と一目でわかります
    @habit       = habits(:habit_one)
    @other_habit = habits(:habit_two)
  end

  # ============================================================
  # private ヘルパーメソッド
  # テストコードの重複を避けるため、ログイン処理を共通化します
  # private にすることで、テストメソッドとして誤認識されるのを防ぎます
  # ============================================================
  private

  # 指定したユーザーでログインするヘルパーメソッド
  # post login_path でセッションを作成します
  def log_in_as(user)
    post login_path, params: {
      session: {
        email:    user.email,
        password: "password"   # fixtures で BCrypt.create("password") と一致
      }
    }
  end

  public

  # ===========================================================
  # ■ 習慣作成テスト
  # ===========================================================

  # ---------------------------------------------------------
  # 正常系: 習慣を正常に作成できること
  # ---------------------------------------------------------
  test "ログイン後に習慣を作成できること" do
    # ① ログイン
    log_in_as(@user)

    # ② 新規作成フォームへアクセス
    get new_habit_path
    # assert_response :success → HTTPステータスが 200 OK であることを確認
    assert_response :success

    # ③ 習慣を作成する
    # assert_difference("Habit.count", 1) → ブロック実行後に Habit.count が 1 増えることを確認
    assert_difference("Habit.count", 1) do
      post habits_path, params: {
        habit: {
          name:          "朝のランニング",
          weekly_target: 5
        }
      }
    end

    # ④ 一覧ページへリダイレクトされることを確認
    # assert_redirected_to → 指定パスへのリダイレクトレスポンスかどうかを確認
    assert_redirected_to habits_path

    # ⑤ リダイレクト先のページを実際に取得
    follow_redirect!

    # ⑥ 成功メッセージが表示されていることを確認
    # assert_select → HTMLの特定要素・テキストが存在するか確認（CSSセレクター形式）
    assert_select "div", text: /習慣を登録しました/

    # ⑦ 作成した習慣がログインユーザーに紐づいていることを確認
    assert_equal @user.id, Habit.order(created_at: :desc).first.user_id
  end

  # ---------------------------------------------------------
  # 異常系: 習慣名が空欄の場合はエラーが表示されること
  # ---------------------------------------------------------
  test "習慣名が空欄の場合はエラーメッセージが表示されること" do
    log_in_as(@user)

    # assert_no_difference → ブロック実行後にカウントが変化しないことを確認
    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name:          "",   # 空欄 → バリデーションエラー
          weekly_target: 7
        }
      }
    end

    # バリデーションエラー時は 422 Unprocessable Entity が返ること
    assert_response :unprocessable_entity

    # エラーボックスが表示されていることを確認
    # bg-red-50 は Tailwind CSS のクラス名（エラーボックスに付与）
    assert_select "div.bg-red-50"
  end

  # ---------------------------------------------------------
  # 異常系: 習慣名が51文字以上の場合はエラーが表示されること
  # ---------------------------------------------------------
  test "習慣名が51文字以上の場合はバリデーションエラーになること" do
    log_in_as(@user)

    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          # "あ" * 51 → 51文字の文字列を生成（バリデーション上限は50文字）
          name:          "あ" * 51,
          weekly_target: 7
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------
  # 異常系: 週次目標値が0以下の場合はエラーになること
  # ---------------------------------------------------------
  test "週次目標値が0の場合はバリデーションエラーになること" do
    log_in_as(@user)

    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name:          "テスト習慣",
          weekly_target: 0   # 0 → バリデーション範囲外（1〜7が有効）
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------
  # 異常系: 週次目標値が8以上の場合はエラーになること
  # ---------------------------------------------------------
  test "週次目標値が8以上の場合はバリデーションエラーになること" do
    log_in_as(@user)

    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name:          "テスト習慣",
          weekly_target: 8   # 8 → バリデーション範囲外（最大7）
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------
  # セキュリティ: 他ユーザーのIDを送っても自分のIDで作成されること
  # Strong Parameters により user_id は許可リストに含まれていないため弾かれます
  # ---------------------------------------------------------
  test "他ユーザーのuser_idを指定しても現在のユーザーIDで作成されること" do
    log_in_as(@user)

    post habits_path, params: {
      habit: {
        name:          "ハッキング試み",
        weekly_target: 7,
        user_id:       @other_user.id   # 不正なuser_id（Strong Parametersで弾かれる）
      }
    }

    # 最後に作成された習慣のuser_idが自分自身であることを確認
    assert_equal @user.id, Habit.order(created_at: :desc).first.user_id
    # 他ユーザーのIDが使われていないことを確認
    assert_not_equal @other_user.id, Habit.order(created_at: :desc).first.user_id
  end

  # ---------------------------------------------------------
  # 未ログイン: ログイン画面にリダイレクトされること
  # ---------------------------------------------------------
  test "未ログイン時は習慣作成ページにアクセスできないこと" do
    # ログインせずに新規作成ページへアクセス
    get new_habit_path
    # require_login によって login_path へリダイレクトされる
    assert_redirected_to login_path
  end

  test "未ログイン時は習慣を作成できないこと" do
    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: { name: "テスト", weekly_target: 7 }
      }
    end
    assert_redirected_to login_path
  end

  # ===========================================================
  # ■ 習慣削除テスト
  # ===========================================================

  # ---------------------------------------------------------
  # 正常系: 習慣を論理削除できること
  # 【論理削除とは？】
  # DBからレコードを消すのではなく、deleted_at に日時を入れることで
  # 「削除済み」扱いにする方法です。過去の記録との整合性を保てます。
  # ---------------------------------------------------------
  test "ログイン後に習慣を論理削除できること" do
    log_in_as(@user)

    # 削除前: active なカウントが1減ること
    assert_difference("@user.habits.active.count", -1) do
      delete habit_path(@habit)
    end

    # 削除後の習慣をDBから再取得（reload しないと古い値のまま）
    @habit.reload
    # deleted_at が nil でない = 論理削除されている
    assert_not_nil @habit.deleted_at,
      "削除後は deleted_at に日時がセットされているはず"

    # 物理削除されていないこと（DBにレコードが残っていること）
    assert Habit.exists?(@habit.id),
      "論理削除なのでDBからレコードは消えないはず"

    # 一覧ページへリダイレクトされること
    assert_redirected_to habits_path

    # 成功メッセージが表示されること
    follow_redirect!
    assert_select "div", text: /習慣を削除しました/
  end

  # ---------------------------------------------------------
  # セキュリティ: 他ユーザーの習慣は削除できないこと
  # ---------------------------------------------------------
  test "他ユーザーの習慣は削除できないこと" do
    log_in_as(@user)

    # 他ユーザーの習慣数は変わらないこと
    assert_no_difference("@other_user.habits.active.count") do
      # @other_habit はユーザー2の習慣（ユーザー1がアクセスしようとしている）
      delete habit_path(@other_habit)
    end

    # エラーメッセージとともに一覧ページへリダイレクト
    assert_redirected_to habits_path
    follow_redirect!
    assert_select "div", text: /習慣が見つかりませんでした/
  end

  # ---------------------------------------------------------
  # 異常系: 論理削除済みの習慣は再度削除できないこと
  # ---------------------------------------------------------
  test "論理削除済みの習慣は再度削除できないこと" do
    log_in_as(@user)

    # @habit を事前に論理削除しておく
    @habit.soft_delete

    # 既に削除済みの習慣を再削除しようとしてもカウントは変わらない
    assert_no_difference("Habit.count") do
      delete habit_path(@habit)
    end

    assert_redirected_to habits_path
    follow_redirect!
    assert_select "div", text: /習慣が見つかりませんでした/
  end

  # ---------------------------------------------------------
  # 未ログイン: 習慣を削除できないこと
  # ---------------------------------------------------------
  test "未ログイン時は習慣を削除できないこと" do
    assert_no_difference("Habit.active.count") do
      delete habit_path(@habit)
    end
    assert_redirected_to login_path
  end

  # ===========================================================
  # ■ 進捗率の表示テスト
  # ===========================================================

  # ---------------------------------------------------------
  # 正常系: 習慣一覧ページで進捗率が表示されること
  # ---------------------------------------------------------
  test "習慣一覧ページで週次進捗率が表示されること" do
    log_in_as(@user)

    get habits_path
    assert_response :success

    # プログレスバーが存在することを確認
    # ビューの実装に合わせてセレクターを調整してください
    assert_select "div.progress-bar, [class*='bg-blue'], [class*='rounded-full']"
  end

  # ---------------------------------------------------------
  # 正常系: 習慣がない場合は Empty State が表示されること
  # ---------------------------------------------------------
  test "習慣が0件の場合はEmpty Stateが表示されること" do
    log_in_as(@user)

    # ユーザー1の全習慣を論理削除
    @user.habits.active.each(&:soft_delete)

    get habits_path
    assert_response :success

    # 習慣が0件の場合に表示されるメッセージを確認
    assert_select "div", text: /まだ習慣が登録されていません/
  end
end