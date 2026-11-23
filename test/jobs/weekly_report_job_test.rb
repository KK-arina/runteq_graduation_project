# test/jobs/weekly_report_job_test.rb
require "test_helper"

class WeeklyReportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
    # ----------------------------------------------------------
    # 【重要】fixture ユーザーの weekly_report_enabled を全て false にリセットする
    # ----------------------------------------------------------
    #
    # 【なぜリセットが必要か】
    #   fixtures :all により test/fixtures/user_settings.yml の全データが
    #   テスト DB に読み込まれる。
    #   fixture の user_settings には weekly_report_enabled: true のレコードが
    #   複数存在するため、このテストで作る @target_user 以外にも
    #   メールが送られてしまい assert_emails の件数が合わなくなる。
    #
    # 【update_all を使う理由】
    #   全レコードを1本の SQL で一括更新できるため高速。
    #   バリデーション・コールバックをスキップするため副作用がない。
    UserSetting.update_all(weekly_report_enabled: false)

    # 送信対象ユーザー（weekly_report_enabled: true・メールアドレスあり）
    @target_user = User.create!(
      name:                  "対象ユーザー",
      email:                 "target@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    # after_create で UserSetting が自動生成される（default: true）
    # 明示的に true を設定してテストの意図を明確にする
    @target_user.user_setting.update!(weekly_report_enabled: true)

    # 非対象ユーザー 1: weekly_report_enabled = false
    @disabled_user = User.create!(
      name:                  "無効ユーザー",
      email:                 "disabled@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    @disabled_user.user_setting.update!(weekly_report_enabled: false)

    # 非対象ユーザー 2: 退会済み
    @deleted_user = User.create!(
      name:                  "退会ユーザー",
      email:                 "deleted@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    @deleted_user.update_column(:deleted_at, Time.current)
  end

  # ============================================================
  # テスト 1: 対象ユーザーにメールが 1 件送信される
  # ============================================================
  test "weekly_report_enabled が true のユーザーにメールが送信される" do
    assert_emails 1 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 2: weekly_report_enabled = false のユーザーにはメールが送られない
  # ============================================================
  test "weekly_report_enabled が false のユーザーにはメールが送信されない" do
    @target_user.user_setting.update!(weekly_report_enabled: false)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 3: 退会済みユーザーにはメールが送られない
  # ============================================================
  test "退会済みユーザーにはメールが送信されない" do
    @target_user.update_column(:deleted_at, Time.current)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 4: 1ユーザーの送信失敗が他ユーザーに影響しない（堅牢性テスト）
  # ============================================================
  test "1人のユーザーへの送信が失敗しても他ユーザーへの送信は継続される" do
    another_user = User.create!(
      name:                  "二人目ユーザー",
      email:                 "another@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    another_user.user_setting.update!(weekly_report_enabled: true)

    original_report = WeeklyReportMailer.method(:report)

    WeeklyReportMailer.stub(:report, ->(user, reflection, stats) {
      if user.id == @target_user.id
        raise StandardError, "テスト用の強制エラー"
      else
        original_report.call(user, reflection, stats)
      end
    }) do
      # @target_user は失敗・another_user は成功 → 合計 1 件
      assert_emails 1 do
        WeeklyReportJob.new.perform
      end
    end
  end

  # ============================================================
  # テスト 5: 先週分の完了記録だけが集計される（record_date 列のバグ修正の確認）
  # ============================================================
  #
  # 【このテストを追加した理由】
  #   以前は集計に存在しない列 recorded_on を使っていたため、
  #   習慣を持つユーザーでは毎回エラーになり、メールが送られていなかった。
  #   テスト 1〜4 のユーザーは習慣を持たないため集計処理が実行されず、
  #   このバグを見つけられなかった。
  #   ここでは習慣と記録を実際に作り、集計の SQL を必ず実行させる。
  test "先週の完了記録だけが habit_stats に集計されてメールに渡される" do
    # 「今日」を 2026-11-23（月）9:00 に固定する
    # 【固定する理由】
    #   「先週」の範囲は実行日によって変わるため、日付を固定しないと
    #   テストを実行する日によって結果が変わってしまう。
    #   この日の先週は 11/16（月）〜 11/22（日）になる。
    travel_to Time.zone.local(2026, 11, 23, 9, 0, 0) do
      habit = Habit.create!(
        user:             @target_user,
        name:             "読書",
        measurement_type: :check_type,
        weekly_target:    7
      )
      # 集計対象は「先週末までに作られた習慣」だけなので、作成日時を過去にずらす
      # （update_column はバリデーションとコールバックを通さずに1列だけ更新する）
      habit.update_column(:created_at, 30.days.ago)

      # 先週の範囲内で完了 → 数える（2件）
      # 11/17・11/18 は「月曜始まり」でも「日曜始まり」でも先週に入る日付
      HabitRecord.create!(user: @target_user, habit: habit, record_date: Date.new(2026, 11, 17), completed: true)
      HabitRecord.create!(user: @target_user, habit: habit, record_date: Date.new(2026, 11, 18), completed: true)

      # 先週の範囲内だが未完了 → 数えない
      HabitRecord.create!(user: @target_user, habit: habit, record_date: Date.new(2026, 11, 19), completed: false)

      # 先週の範囲外（2週間前と今日）→ 数えない
      HabitRecord.create!(user: @target_user, habit: habit, record_date: Date.new(2026, 11, 10), completed: true)
      HabitRecord.create!(user: @target_user, habit: habit, record_date: Date.new(2026, 11, 23), completed: true)

      # メーラーに渡された stats を記録しておく入れ物
      captured_stats = nil
      original_report = WeeklyReportMailer.method(:report)

      # 本物のメーラーを呼びつつ、渡された stats だけを横取りして記録する
      WeeklyReportMailer.stub(:report, ->(user, reflection, stats) {
        captured_stats = stats if user.id == @target_user.id
        original_report.call(user, reflection, stats)
      }) do
        assert_emails 1 do
          WeeklyReportJob.new.perform
        end
      end

      # 集計でエラーになるとメーラーまで届かず captured_stats が nil のままになる
      assert_not_nil captured_stats, "集計中にエラーが起きてメーラーが呼ばれていません"
      assert_equal 1, captured_stats.size

      stat = captured_stats.first
      assert_equal "読書", stat[:name]
      assert_equal 2, stat[:completed]
    end
  end
end
