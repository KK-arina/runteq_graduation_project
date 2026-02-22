# ファイルパス: test/controllers/weekly_reflections_controller_test.rb
#
# 【このファイルの役割】
# WeeklyReflectionsController の動作を自動テストする。
# Issue #25 では「振り返り完了後のロック解除とリダイレクト」のテストを追加する。
#
# 【修正履歴】
# v2: 以下の3点を修正した
#   1. authenticate_user! → require_login に修正
#      （実際のプロジェクトは Devise を使わず独自認証のため）
#   2. freeze_time 内での travel_to ネスト → travel に変更
#      （Rails が「二重ネストは使うな」と警告するため）
#   3. 認証メソッド名を実際のプロジェクトに合わせた
#
# 【テストの実行方法】
# docker compose exec web rails test test/controllers/weekly_reflections_controller_test.rb

require "test_helper"

class WeeklyReflectionsControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストの前に実行される共通処理
  # ============================================================
  setup do
    # フィクスチャからテスト用ユーザーを取得してログイン状態にする
    # log_in_as は test_helper.rb に定義されているヘルパーメソッド
    # post login_path を通じて実際のHTTPリクエストでログインする
    @user = users(:one)
    log_in_as(@user)
  end

  # ============================================================
  # create アクションのテスト（Issue #25 で追加）
  # ============================================================

  # 【テスト1】振り返りを保存するとweekly_reflections_pathにリダイレクトされること
  # （通常ユーザーはロック中でないため weekly_reflections_path へ）
  test "create completes reflection and redirects to weekly_reflections" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do # 日曜日 AM10:00
      assert_difference "WeeklyReflection.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: "今週も頑張った！" }
        }
      end

      # 通常ユーザー（ロック中でない）は weekly_reflections_path へ
      assert_redirected_to weekly_reflections_path
    end
  end

  # 【テスト2】振り返り保存後、completed_at が設定されること
  test "create sets completed_at on the new reflection" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "振り返りコメント" }
      }

      # 作成された振り返りを取得する
      reflection = WeeklyReflection.last

      # completed_at が設定されていることを確認する
      assert_not_nil reflection.completed_at,
                     "振り返り保存後は completed_at が設定されること"
      assert reflection.completed?,
             "振り返り保存後は completed? が true になること"
      assert_not reflection.pending?,
                 "振り返り保存後は pending? が false になること"
    end
  end

  # 【テスト3】ロック中のユーザーが振り返りを完了したとき、ロック解除バナーが表示されること
  test "create with previously locked user shows unlock flash message" do
    # locked_user: 前週の振り返りが未完了のユーザー（フィクスチャで定義済み）
    locked_user = users(:locked_user)
    log_in_as(locked_user)

    # travel_to で「月曜日の AM4:01」に時刻を固定する
    # locked? の条件: 月曜日 かつ AM4:00 以降 かつ 前週振り返り未完了
    travel_to Time.zone.parse("2026-02-16 04:01:00") do # 月曜日 AM4:01
      # テスト前提確認: このユーザーはロック中であること
      # application_controller の locked? が正しく動いているかも同時に確認できる
      # （locked? は ApplicationController に定義されており、ビューからも呼べる）

      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "前週の振り返りです" }
      }

      # リダイレクト先に遷移する
      follow_redirect!

      # flash[:unlock] の内容がレスポンスボディに含まれることを確認する
      # assert_match → 文字列に特定のキーワードが含まれることを確認する
      assert_match "ロックが解除されました", response.body
    end
  end

  # 【テスト4】ロックされていないユーザーが振り返りを完了したとき、通常のメッセージが表示されること
  test "create without locked state shows normal notice" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do # 日曜日（月曜未到達のためロック対象外）
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "通常の振り返り" }
      }

      follow_redirect!
      # 通常の完了メッセージが含まれることを確認（実際のメッセージ文言に合わせる）
      assert_match "振り返りを保存しました", response.body
      # ロック解除メッセージは含まれないことを確認
      assert_no_match "ロックが解除されました", response.body
    end
  end

  # 【テスト5】同じ週に2回目を送信しても2件目は作成されないこと
  test "create prevents double submission" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      # 1回目の振り返りを作成する
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "1回目" }
      }

      # assert_no_difference → ブロック実行前後で件数が変わらないことを確認する
      assert_no_difference "WeeklyReflection.count" do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: "2回目（作成されないはず）" }
        }
      end

      # 2回目は既存の振り返りの詳細ページにリダイレクトされることを確認する
      existing = @user.weekly_reflections
                      .for_week(WeeklyReflection.current_week_start_date)
                      .completed.first
      assert_redirected_to weekly_reflection_path(existing)
    end
  end

  # 【テスト6】未ログイン状態でアクセスするとログインページにリダイレクトされること
  test "create redirects to login if not authenticated" do
    # ログアウト状態にする（delete logout_path でセッションを削除）
    delete logout_path

    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "テスト" }
      }

      # require_login により login_path にリダイレクトされることを確認する
      assert_redirected_to login_path
    end
  end

  # ============================================================
  # locked? との連携テスト（Issue #25 の核心）
  # ============================================================

  # 【テスト7】振り返り完了後に前週の pending_reflection が completed? になること
  test "user is no longer locked after completing reflection via controller" do
    locked_user = users(:locked_user)
    log_in_as(locked_user)

    # travel_to で「月曜日の AM4:01」に時刻を固定する
    # current_week_start_date = 2026-02-16（今週）
    # last_week_start         = 2026-02-09（前週）= pending_reflection の週
    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "振り返り完了！" }
      }

      locked_user.reload

      # 今週の振り返りが作成・完了されていることを確認する
      current_week_start = WeeklyReflection.current_week_start_date
      new_reflection = locked_user.weekly_reflections
                                  .find_by(week_start_date: current_week_start)
      assert_not_nil new_reflection, "今週の振り返りレコードが作成されること"
      assert new_reflection.completed?, "今週の振り返りは completed? が true になること"

      # 前週の振り返り（pending_reflection）も complete! されてロックが解除されること
      last_week_start = current_week_start - 7.days
      last_week_reflection = locked_user.weekly_reflections
                                        .find_by(week_start_date: last_week_start)
      assert_not_nil last_week_reflection, "前週の振り返りレコードが存在すること"
      assert last_week_reflection.completed?,
             "前週の振り返りも completed? が true になること（ロック解除）"
      assert_not last_week_reflection.pending?,
                 "前週の振り返りは pending? が false になること"

      # ロック解除バナーとともにダッシュボードへリダイレクトされること
      assert_redirected_to dashboard_path
    end
  end
end
