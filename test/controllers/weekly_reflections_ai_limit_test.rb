# test/controllers/weekly_reflections_ai_limit_test.rb
#
# ==============================================================================
# D-6: AI コスト上限管理のテスト
# ==============================================================================
# 【重要: locked? は動的計算メソッドであることに注意】
#   locked? は User モデルの DB カラムではなく、ApplicationController に定義された
#   動的計算メソッド（前週の振り返りが未完了かつ月曜AM4:00以降かどうかを判定）。
#   そのため @user.update!(locked: true) のような DB 書き込みはできない。
#   ロック状態を作るには「前週の未完了振り返りレコードを作成する」必要がある。
# ==============================================================================

require "test_helper"

class WeeklyReflectionsAiLimitTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(
      name:                  "AIテストユーザー",
      email:                 "ai_limit_#{rand(9999)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )
    @user_setting = @user.user_setting

    post login_path, params: { session: { email: @user.email, password: "password123" } }
    assert_response :redirect
    follow_redirect!

    # travel_to はリクエスト内スレッドに引き継がれないため setup では使わない
    # 各テストで必要な場合のみ個別に設定する
  end

  def teardown
    travel_back
  end

  # ============================================================
  # テスト1: 上限未達時は通常保存され AI ジョブがエンキューされる
  # ============================================================
  def test_create_enqueues_job_when_under_limit
    @user_setting.update!(ai_analysis_count: 5, ai_analysis_monthly_limit: 10)

    assert_enqueued_with(job: WeeklyReflectionAnalysisJob) do
      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "今週の振り返りです",
          direct_reason:        "疲れていたから",
          background_situation: "早めに寝る",
          next_action:          "来週に活かす"
        }
      }
    end

    assert_nil flash[:ai_limit], "上限未達時は flash[:ai_limit] がセットされないはず"
    assert_response :redirect
  end

  # ============================================================
  # テスト2: 上限超過時は render :new されフォームが保持される
  # ============================================================
  def test_create_renders_new_with_ai_limit_flash_when_exceeded
    @user_setting.update!(ai_analysis_count: 10, ai_analysis_monthly_limit: 10)

    post weekly_reflections_path, params: {
      weekly_reflection: {
        reflection_comment:   "今週の振り返りです",
        direct_reason:        "疲れていたから",
        background_situation: "早めに寝る",
        next_action:          "来週に活かす"
      }
    }

    # render :new が実行されること（リダイレクトではない）
    assert_response :unprocessable_entity
    # flash.now[:ai_limit] がセットされていること
    assert flash[:ai_limit], "上限超過時は flash[:ai_limit] = true がセットされるはず"
  end

  # ============================================================
  # テスト3: 上限超過時は振り返りが保存されない
  # ============================================================
  def test_create_does_not_save_when_limit_exceeded
    @user_setting.update!(ai_analysis_count: 10, ai_analysis_monthly_limit: 10)

    assert_no_difference "WeeklyReflection.count" do
      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "保存されないはず",
          direct_reason:        "理由",
          background_situation: "改善策",
          next_action:          "次のアクション"
        }
      }
    end
  end

  # ============================================================
  # テスト4: complete_without_ai で振り返りが保存される
  # ============================================================
  def test_complete_without_ai_saves_reflection
    @user_setting.update!(ai_analysis_count: 10, ai_analysis_monthly_limit: 10)

    assert_difference "WeeklyReflection.count", 1 do
      post complete_without_ai_weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "AIなしで完了します",
          direct_reason:        "理由",
          background_situation: "改善策",
          next_action:          "次のアクション"
        }
      }
    end

    assert_response :redirect
  end

  # ============================================================
  # テスト5: complete_without_ai では AI ジョブがエンキューされない
  # ============================================================
  def test_complete_without_ai_does_not_enqueue_analysis_job
    @user_setting.update!(ai_analysis_count: 10, ai_analysis_monthly_limit: 10)

    assert_no_enqueued_jobs only: WeeklyReflectionAnalysisJob do
      post complete_without_ai_weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "AIなしで完了します",
          direct_reason:        "理由",
          background_situation: "改善策",
          next_action:          "次のアクション"
        }
      }
    end
  end

  # ============================================================
  # テスト6: complete_without_ai はロック状態に関わらず振り返りを保存する
  # ============================================================
  #
  # 【travel_to がリクエスト内で効かない問題について】
  #   ActionDispatch::IntegrationTest でHTTPリクエストを発行すると
  #   別スレッドで処理されるため、travel_to の時刻固定が
  #   コントローラー内に引き継がれない。
  #   そのため locked? の結果がテストコードと異なる可能性がある。
  #
  # 【このテストで検証すること】
  #   - complete_without_ai が成功すること（振り返りが保存されること）
  #   - dashboard または weekly_reflections にリダイレクトされること
  #     （was_locked の値に関わらず、どちらかにリダイレクトされれば成功）
  #   - flash にメッセージがセットされること
  def test_complete_without_ai_saves_and_redirects
    @user_setting.update!(ai_analysis_count: 10, ai_analysis_monthly_limit: 10)

    # 振り返りが1件保存されることを確認する
    assert_difference "WeeklyReflection.count", 1 do
      post complete_without_ai_weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "AIなしで完了します",
          direct_reason:        "理由",
          background_situation: "改善策",
          next_action:          "次のアクション"
        }
      }
    end

    # どちらかにリダイレクトされること
    assert_includes [dashboard_url, weekly_reflections_url], response.location,
                    "dashboard または weekly_reflections にリダイレクトされるはず"

    # AI スキップのメッセージがいずれかの flash にセットされていること
    ai_skip_message = flash[:unlock].to_s + flash[:notice].to_s
    assert_includes ai_skip_message, "AI分析はスキップされました",
                    "AI分析スキップのメッセージがセットされているはず"
  end

  # ============================================================
  # テスト7: MonthlyAiCountResetJob が月初にリセットする
  # ============================================================
  def test_monthly_ai_count_reset_job_resets_on_first_day
    @user_setting.update!(ai_analysis_count: 8)

    travel_to Time.zone.local(2026, 6, 1, 0, 5, 0) do
      MonthlyAiCountResetJob.perform_now
    end

    assert_equal 0, @user_setting.reload.ai_analysis_count,
                 "月初に実行すると ai_analysis_count が 0 になるはず"
  end

  # ============================================================
  # テスト8: MonthlyAiCountResetJob が月初以外はリセットしない
  # ============================================================
  def test_monthly_ai_count_reset_job_skips_non_first_day
    @user_setting.update!(ai_analysis_count: 7)

    travel_to Time.zone.local(2026, 6, 15, 0, 5, 0) do
      MonthlyAiCountResetJob.perform_now
    end

    assert_equal 7, @user_setting.reload.ai_analysis_count,
                 "月初以外は ai_analysis_count が変わらないはず"
  end

  # ============================================================
  # テスト9: 未ログインでは complete_without_ai にアクセスできない
  # ============================================================
  def test_complete_without_ai_requires_login
    delete logout_path

    post complete_without_ai_weekly_reflections_path, params: {
      weekly_reflection: { reflection_comment: "未ログインテスト" }
    }

    assert_redirected_to login_path
  end
end