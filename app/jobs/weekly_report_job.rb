# app/jobs/weekly_report_job.rb
#
# ==============================================================================
# WeeklyReportJob - 週次レポートメール送信ジョブ
# ==============================================================================
#
# 【このジョブの役割】
#   GoodJob cron により毎週月曜日 AM9:00（JST）に自動実行され、
#   週次レポートメールの送信対象ユーザーを絞り込み、
#   各ユーザーに WeeklyReportMailer#report を呼んでメールを送信する。
#
# 【実行タイミング】
#   config/initializers/good_job.rb の cron 設定に登録済み。
#   JST 9:00 = UTC 0:00 → cron: "0 0 * * 1"（毎週月曜日 UTC 00:00）
#
# 【設計原則】
#   - トランザクション内は DB アクセスのみ（外部 API = メール送信はトランザクション外）
#   - 1ユーザーのメール送信失敗が他ユーザーに影響しないよう begin~rescue をループ内に配置
#   - deliver_now を使う（このジョブ自体が非同期なので deliver_later は二重ジョブになる）
#
# ==============================================================================
class WeeklyReportJob < ApplicationJob

  # ============================================================
  # キュー設定
  # ============================================================
  #
  # 【queue_as :default の理由】
  #   :default キューは GoodJob の標準キュー。
  #   週次レポートは緊急性が低いため専用キューは不要。
  queue_as :default

  # ============================================================
  # perform メソッド
  # ============================================================
  def perform
    Rails.logger.info "[WeeklyReportJob] 週次レポート送信開始"

    # ----------------------------------------------------------
    # Step 1: 先週の期間を計算する
    # ----------------------------------------------------------
    #
    # 【WeeklyReflection.current_week_start_date を使う理由】
    #   「現在時刻 - 4時間」の beginning_of_week(:monday) を返すクラスメソッド。
    #   HabitFlow の「1日の境界が AM4:00」というルールに準拠している。
    #   ジョブは月曜日 AM9:00 JST に実行されるため
    #   この時点での current_week_start = 本日（月曜日）になる。
    #   そこから 7 日引いて「先週の月曜日」を取得する。
    last_week_start = WeeklyReflection.current_week_start_date - 7.days
    last_week_end   = last_week_start + 6.days

    Rails.logger.info "[WeeklyReportJob] 対象期間: #{last_week_start} 〜 #{last_week_end}"

    # ----------------------------------------------------------
    # Step 2: 送信対象ユーザーを取得する
    # ----------------------------------------------------------
    #
    # 【User.active の説明】
    #   User モデルの scope :active → deleted_at IS NULL のユーザーのみ取得
    #   退会済みユーザーへの誤送信を防ぐ
    #
    # 【joins(:user_setting) の説明】
    #   user_settings テーブルを INNER JOIN して WHERE 条件に使えるようにする
    #   includes ではなく joins を使う理由:
    #   WHERE 条件を user_settings カラムに掛けるだけなら joins で十分。
    #   includes は関連レコードをメモリに展開するため不要なコストを避ける。
    #
    # 【where(user_settings: { weekly_report_enabled: true }) の説明】
    #   週次レポートメールを受け取る設定が ON のユーザーのみに絞り込む
    #
    # 【where.not(email: nil) の説明】
    #   LINE ログインユーザーは email が NULL の場合がある（User モデルの仕様）
    #   メールアドレスがないユーザーには送信できないため除外する
    #
    # 【includes(:user_setting) の説明】
    #   joins でフィルタリングした後、ループ内で user.user_setting を
    #   参照する可能性があるため includes で事前読み込みして N+1 を防ぐ
    target_users = User.active
                       .joins(:user_setting)
                       .where(user_settings: {
                         weekly_report_enabled:  true,
                         notification_enabled:   true   # G-3 修正: マスタースイッチがONのユーザーのみ
                       })
                       .where.not(email: nil)
                       .includes(:user_setting)

    Rails.logger.info "[WeeklyReportJob] 送信対象ユーザー数: #{target_users.count}"

    # ----------------------------------------------------------
    # Step 3: 各ユーザーにメールを送信する
    # ----------------------------------------------------------
    #
    # 【ループ内で begin ~ rescue を使う理由】
    #   1人のユーザーへのメール送信が失敗しても rescue でキャッチして
    #   次のユーザーの処理を続けられるようにするため。
    #   begin ~ rescue をループの外に置くと、1人失敗した時点で
    #   残り全員へのメール送信が中断されてしまう。
    sent_count   = 0
    failed_count = 0

    target_users.each do |user|
      begin
        send_report_to(user, last_week_start, last_week_end)
        sent_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "[WeeklyReportJob] ユーザー ID=#{user.id} への送信失敗: " \
                           "#{e.class} - #{e.message}"
      end
    end

    Rails.logger.info "[WeeklyReportJob] 週次レポート送信完了: " \
                      "成功=#{sent_count}, 失敗=#{failed_count}"
  end

  private

  # ==============================================================
  # send_report_to - 1ユーザーへのレポート送信処理
  # ==============================================================
  #
  # 【private メソッドに切り出す理由】
  #   perform メソッドが肥大化しないよう1ユーザー分の処理を別メソッドにまとめる。
  #   テスト時もこのメソッド単体でテストしやすくなる。
  def send_report_to(user, last_week_start, last_week_end)
    # --------------------------------------------------------
    # Step A: 先週の完了済み週次振り返りを取得する
    # --------------------------------------------------------
    #
    # 【scope :for_week の説明】
    #   week_start_date = last_week_start のレコードを絞り込む
    # 【scope :completed の説明】
    #   completed_at IS NOT NULL のレコードのみを対象にする
    # 【.first の説明】
    #   振り返りは週1件が原則だが念のため first で1件取得する
    #   振り返りがない場合は nil が返り、Mailer 側で「未提出」表示になる
    reflection = user.weekly_reflections
                     .for_week(last_week_start)
                     .completed
                     .first

    # --------------------------------------------------------
    # Step B: 先週の習慣達成率を計算する
    # --------------------------------------------------------
    habit_stats = calculate_habit_stats(user, last_week_start, last_week_end)

    # --------------------------------------------------------
    # Step C: メール送信
    # --------------------------------------------------------
    #
    # 【deliver_now を使う理由】
    #   このジョブ自体が GoodJob の非同期ジョブとして実行されているため
    #   deliver_later を使うと「ジョブの中でジョブを登録する」二重構造になる。
    #   deliver_now で同期送信することでシンプルな処理フローを維持する。
    WeeklyReportMailer.report(user, reflection, habit_stats).deliver_now

    Rails.logger.info "[WeeklyReportJob] 送信成功: user_id=#{user.id}"
  end

  # ==============================================================
  # calculate_habit_stats - 習慣達成率の計算
  # ==============================================================
  #
  # 【habit_records を直接集計する理由】
  #   WeeklyReflectionHabitSummary（スナップショット）は
  #   振り返り完了時にのみ作成されるため、振り返り未完了ユーザーには使えない。
  #   habit_records を直接集計することで全ユーザーに対応できる。
  #
  # 【measurement_type: :check_type を使う理由】
  #   Habit モデルの enum 定義を確認した結果:
  #     enum :measurement_type, { check_type: 0, numeric_type: 1 }
  #   カラム名は「habit_type」ではなく「measurement_type」が正しい。
  #   （docker compose exec web bin/rails runner
  #    "puts Habit.defined_enums.inspect" で確認済み）
  #
  # 【check_type のみ対象にする理由】
  #   数値型（numeric_type）は weekly_target との数値比較が必要で複雑になる。
  #   週次レポートメールは簡潔さを優先し、チェック型のみを対象にする。
  #
  # 【戻り値】
  #   Array of Hash: [{ name:, rate:, completed:, target: }, ...]
  #   習慣が 0 件の場合は空配列 [] を返す
  def calculate_habit_stats(user, last_week_start, last_week_end)
    habits = user.habits
                 .where(measurement_type: :check_type)
                 .where(archived_at: nil)
                 .where("created_at <= ?", last_week_end.end_of_day)

    habits.map do |habit|
      # 先週の完了レコード数を集計する
      # recorded_on: 先週月曜〜日曜の範囲で絞り込む
      # completed: true のみカウント（除外日・スキップは false）
      completed_count = habit.habit_records
                             .where(recorded_on: last_week_start..last_week_end)
                             .where(completed: true)
                             .count

      # effective_weekly_target: 除外日を考慮した実際の目標日数を分母にする
      # （土日除外設定なら 5、除外なしなら 7 になる）
      target = habit.effective_weekly_target

      # ゼロ除算防止（除外日設定によって target が 0 になる場合がある）
      rate = if target.zero?
               0
             else
               ((completed_count.to_f / target) * 100).round
             end

      # 目標以上に達成した場合に 100% を超えることがあるため上限を設ける
      rate = rate.clamp(0, 100)

      {
        name:      habit.name,
        rate:      rate,
        completed: completed_count,
        target:    target
      }
    end
  end
end