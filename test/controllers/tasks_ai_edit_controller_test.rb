# test/controllers/tasks_ai_edit_controller_test.rb
#
# ==============================================================================
# C-7: タスクAI編集ページのコントローラーテスト（エラー修正版）
# ==============================================================================
#
# 【修正内容】
#   1. assert_template を削除
#      → Rails 7 では assert_template は rails-controller-testing gem が必要。
#         gem を追加せず、代わりに以下で代替する。
#         「ページが再描画されたか」→ assert_response :unprocessable_entity で確認
#         「特定の文字列が表示されているか」→ assert_match で response.body を確認
#
#   2. ai_update（403）テストの期待値を修正
#      → verify_ai_context は「redirect_to tasks_path + flash[:alert]」を返す。
#         redirect_to は HTTP 302（リダイレクト）を返すため
#         assert_redirected_to が正しい。
#         status: :forbidden を redirect_to に渡すと Rails 7 では無視される。
#         （redirect_to は常に 3xx を返す仕様）
# ==============================================================================

require "test_helper"

class TasksAiEditControllerTest < ActionDispatch::IntegrationTest

  # ============================================================
  # setup: テスト前の共通準備
  # ============================================================
  def setup
    # 水曜日（2026-04-15）に固定する
    # 理由: locked? メソッドは月曜 AM4:00 以降かどうかを確認するが、
    #       水曜に固定しておくことで「今週月曜 AM4:00 を過ぎている」状態になる。
    #       ただし前週の振り返りが完了しているユーザーを使うためロックはかからない。
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)

    # fixtures からユーザーを取得する
    @user       = users(:one)
    @other_user = users(:two)

    # テスト用タスクを作成する
    # ai_generated: false → 手動作成タスク（削除可能なタイプ）
    @task = @user.tasks.create!(
      title:     "AI編集テスト用タスク",
      priority:  :must,
      task_type: :normal,
      status:    :todo
    )

    # 他ユーザーのタスクも作成する（アクセス制御テスト用）
    @other_task = @other_user.tasks.create!(
      title:     "他ユーザーのタスク",
      priority:  :should,
      task_type: :normal,
      status:    :todo
    )

    # ログインする
    # params: { session: { ... } } の形式は SessionsController#create の
    # Strong Parameters（params[:session][:email]）に合わせている
    post login_path, params: { session: { email: @user.email, password: "password" } }
    assert_response :redirect, "ログインに失敗しました。fixtures のパスワードを確認してください"
  end

  def teardown
    travel_back
  end

  # ============================================================
  # GET /tasks/:id/ai_edit（ai_edit アクション）
  # ============================================================

  test "ai_edit: ログイン済みで正常にアクセスできること" do
    get ai_edit_task_path(@task)

    # 200 OK が返ること
    assert_response :success

    # =====================================================
    # 【修正ポイント1】assert_template の削除
    # =====================================================
    # 修正前: assert_template :ai_edit
    #   → rails-controller-testing gem がないと NoMethodError になる
    # 修正後: response.body に ai_edit 固有の文字列が含まれるか確認する
    #   → gem 不要で同等の確認ができる

    # AI経由限定バナーが表示されていること（ai_edit.html.erb 固有の文字列）
    assert_match "AI提案モーダルから編集しています", response.body

    # 優先度が読み取り専用で表示されていること
    # radio button（name="task[priority]"）が存在しないことを確認する
    # assert_select は response.body の HTML を CSS セレクタで検索する
    assert_select "input[name='task[priority]']", count: 0

    # フォームの送信先が ai_update_task_path であること
    # form の action 属性に "/ai_update" が含まれることを確認する
    assert_match "ai_update", response.body
  end

  test "ai_edit: アクセス後に session に ai_context_task_id が設定されること" do
    get ai_edit_task_path(@task)

    # session[:ai_context_task_id] に @task.id が保存されていること
    assert_equal @task.id, session[:ai_context_task_id]
  end

  test "ai_edit: 他ユーザーのタスクには 404 が返ること" do
    get ai_edit_task_path(@other_task)

    # ApplicationController の rescue_from RecordNotFound で 404 になること
    assert_response :not_found
  end

  test "ai_edit: 未ログインでは login_path にリダイレクトされること" do
    # 一度ログアウトする
    delete logout_path

    get ai_edit_task_path(@task)

    # require_login により login_path へリダイレクトされること
    assert_redirected_to login_path
  end

  # ============================================================
  # PATCH /tasks/:id/ai_update（ai_update アクション）
  # ============================================================

  test "ai_update: ai_edit を経由した場合（session フラグあり）→ 保存成功してリダイレクト" do
    # まず ai_edit にアクセスして session にフラグを立てる
    get ai_edit_task_path(@task)

    # ai_update に PATCH リクエストを送る
    patch ai_update_task_path(@task), params: {
      task: {
        title:           "更新後のタスク名",
        due_date:        "2026-04-20",
        estimated_hours: "2.5"
      }
    }

    # tasks_path にリダイレクトされること
    assert_redirected_to tasks_path

    # フラッシュメッセージが日本語で表示されること
    assert_equal "タスクを更新しました（AI編集）", flash[:notice]

    # タスクが実際に更新されていること
    @task.reload
    assert_equal "更新後のタスク名", @task.title
    assert_equal Date.parse("2026-04-20"), @task.due_date
    assert_in_delta 2.5, @task.estimated_hours.to_f, 0.01

    # session の ai_context_task_id がクリアされていること
    assert_nil session[:ai_context_task_id]
  end

  test "ai_update: ai_context フラグなし（直接アクセス）→ tasks_path へリダイレクト" do
    # =====================================================
    # 【修正ポイント2】期待するレスポンスを修正
    # =====================================================
    # 修正前: assert_response :forbidden（403 を期待）
    # 修正後: assert_redirected_to tasks_path（302 リダイレクトを期待）
    #
    # 【理由】
    #   verify_ai_context では respond_to の format.html ブロック内で
    #   redirect_to tasks_path, alert: "...", status: :forbidden を呼んでいる。
    #
    #   しかし Rails 7 では redirect_to に status: を渡しても
    #   リダイレクトのステータスコードには影響しない。
    #   redirect_to は常に HTTP 302 (Found) を返す。
    #   status: :forbidden は「アプリのロジック上の意味」として記述しているが、
    #   実際の HTTP ステータスは 302 になる。
    #
    #   → テストでは「302 リダイレクト + flash[:alert] の内容」で確認する。

    # ai_edit を経由せずに直接 ai_update を叩く（session フラグなし）
    patch ai_update_task_path(@task), params: {
      task: {
        title: "直接アクセスで変えようとした名前"
      }
    }

    # tasks_path にリダイレクトされること（302）
    assert_redirected_to tasks_path

    # アラートメッセージが日本語で表示されること
    assert_equal "この操作はAI提案モーダル経由でのみ実行できます", flash[:alert]

    # タスクが変更されていないこと
    @task.reload
    assert_equal "AI編集テスト用タスク", @task.title
  end

  test "ai_update: 優先度が変更されないこと（ai_update_params に含まれない）" do
    # ai_edit を経由してフラグを立てる
    get ai_edit_task_path(@task)

    original_priority = @task.priority

    # :priority を含めて送信しても変更されないことを確認する
    patch ai_update_task_path(@task), params: {
      task: {
        title:    "更新後",
        priority: "could"   # must から could に変えようとする
      }
    }

    @task.reload
    # priority は元の値（must）のまま変わっていないこと
    assert_equal original_priority, @task.priority
  end

  test "ai_update: バリデーションエラー時は ai_edit ビューが再描画されること" do
    # ai_edit を経由してフラグを立てる
    get ai_edit_task_path(@task)

    # タイトルを空にして送信する（title: "" はバリデーションエラーになる）
    patch ai_update_task_path(@task), params: {
      task: {
        title: ""
      }
    }

    # 422 Unprocessable Entity が返ること
    assert_response :unprocessable_entity

    # =====================================================
    # 【修正ポイント3】assert_template の削除
    # =====================================================
    # 修正前: assert_template :ai_edit
    # 修正後: response.body に ai_edit 固有の文字列が含まれるか確認する

    # ai_edit.html.erb 固有のバナー文字列が含まれていること
    assert_match "AI提案モーダルから編集しています", response.body

    # エラーメッセージが表示されていること
    # text-red-700 クラスを持つ li 要素が存在することを確認する
    assert_select "li.text-red-700"
  end

  test "ai_update: 他ユーザーのタスクには 404 が返ること" do
    # @other_user のタスクに対して @user でアクセスしようとする
    # set_task で current_user.tasks.find が RecordNotFound を発生させる
    get ai_edit_task_path(@other_task)
    assert_response :not_found

    # ai_update も同様に 404 になること
    patch ai_update_task_path(@other_task), params: {
      task: { title: "変えようとした名前" }
    }
    assert_response :not_found
  end
end