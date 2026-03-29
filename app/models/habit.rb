# app/models/habit.rb
#
# ==============================================================================
# Habit（習慣）モデル（B-3: ストリーク計算対応）
# ==============================================================================
#
# 【B-3 での変更内容】
#
#   ① calculate_streak! メソッドを追加
#   ② on_rest_mode? メソッドを追加
#   ③ rest_mode_on_date?（新規）メソッドを追加（B-3 修正）
#      「指定日にお休みモードが適用されていたか」を返す。
#      on_rest_mode? は「今この瞬間のお休みモード状態」を返すだけなので、
#      過去日付の判定には使えない。
#      例: 昨日お休みモードが終了していた場合に
#          on_rest_mode? は false を返すが、
#          昨日は rest_mode_until 以前なので「昨日はお休みモード中」だった。
#      rest_mode_on_date?(date) で日付単位の判定をすることで
#      この問題を解決する。
#
# ==============================================================================

class Habit < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  belongs_to :user
  has_many :habit_records, dependent: :destroy
  has_many :weekly_reflection_habit_summaries, dependent: :nullify
  has_many :habit_excluded_days, dependent: :destroy

  # ============================================================
  # Enum 定義
  # ============================================================

  enum :measurement_type, {
    check_type:   0,
    numeric_type: 1
  }

  # ============================================================
  # バリデーション
  # ============================================================

  validates :name, presence: true, length: { maximum: 50 }

  validates :weekly_target,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              message: "は1以上の整数を入力してください"
            }

  validates :weekly_target,
            numericality: {
              less_than_or_equal_to: 7,
              message: "は7以下で設定してください（チェック型は週7日が最大）"
            },
            if: -> { check_type? }

  validates :measurement_type, presence: true,
                                inclusion: {
                                  in: measurement_types.keys,
                                  message: "は有効な値を選択してください"
                                }

  validates :unit,
            presence: {
              message: "は数値型習慣では入力が必要です"
            },
            length: { maximum: 10 },
            if: -> { numeric_type? }

  # ============================================================
  # スコープ
  # ============================================================

  scope :active,   -> { where(deleted_at: nil) }
  scope :deleted,  -> { where.not(deleted_at: nil) }

  # ============================================================
  # インスタンスメソッド（既存）
  # ============================================================

  def soft_delete
    touch(:deleted_at)
  end

  def active?
    deleted_at.nil?
  end

  def deleted?
    !active?
  end

  def excluded_day_numbers
    habit_excluded_days.pluck(:day_of_week).sort
  end

  def effective_weekly_target
    excluded_count = habit_excluded_days.size
    available_days = 7 - excluded_count
    [ weekly_target, available_days ].min
  end

  # ============================================================
  # B-3 追加: ストリーク関連メソッド
  # ============================================================

  # on_rest_mode?
  # 【役割】
  #   「このユーザーが現在（今この瞬間）お休みモード中か」を返す。
  #   ストリーク計算では rest_mode_on_date? を使うため、
  #   このメソッドは外部から呼ぶ用途（UI表示など）のために残している。
  #
  # 【&. (safe navigation operator) を使う理由】
  #   user_setting が存在しないユーザーの場合に NoMethodError が発生するのを防ぐ。
  #   &. は左辺が nil の場合に nil を返してメソッドを呼ばない。
  def on_rest_mode?
    user.user_setting&.rest_mode_active?
  end

  # rest_mode_on_date?（B-3 修正追加）
  # 【役割】
  #   「指定した日付に、このユーザーのお休みモードが有効だったか」を返す。
  #
  # 【なぜ on_rest_mode? ではなく rest_mode_on_date? を使うのか】
  #   on_rest_mode? は「今この瞬間」のお休みモード状態を返す。
  #   ストリーク計算では過去の日付（昨日・一昨日など）を遡って判定するため、
  #   「その日にお休みモードが有効だったか」を日付単位で確認する必要がある。
  #
  # 【仕組み】
  #   user_setting.rest_mode_until が設定されており、
  #   かつ rest_mode_until.to_date が date 以上（= dateはまだお休み期間内）なら
  #   そのユーザーはその日もお休みモード中だったと判定できる。
  #
  # 【引数】
  #   date: 判定したい日付（Date オブジェクト）
  #
  # 【例】
  #   rest_mode_until = 2026-04-10（金）と設定されている場合:
  #   rest_mode_on_date?(Date.new(2026, 4, 8))  → true  （4/8はお休み期間内）
  #   rest_mode_on_date?(Date.new(2026, 4, 10)) → true  （4/10はお休み最終日）
  #   rest_mode_on_date?(Date.new(2026, 4, 11)) → false （4/11はお休み終了後）
  def rest_mode_on_date?(date)
    # allow_rest_mode が false の習慣はお休みモードを適用しない
    return false unless allow_rest_mode

    # user_setting が存在しない場合は false
    setting = user.user_setting
    return false unless setting

    # rest_mode_until が設定されていない場合は false
    return false unless setting.rest_mode_until.present?

    # rest_mode_until の「日付部分」が date 以上ならその日はお休みモード中
    # to_date でタイムゾーンの影響を排除して日付のみで比較する
    setting.rest_mode_until.to_date >= date
  end

  # calculate_streak!
  # 【役割】
  #   今日時点のストリーク（連続達成日数）を計算して
  #   habits.current_streak と habits.longest_streak を更新する。
  #
  # 【引数】
  #   reference_date: 計算基準日（デフォルトは HabitRecord.today_for_record）
  #
  # 【ストリーク計算のアルゴリズム】
  #   1. 基準日から過去に向かって1日ずつさかのぼる
  #   2. その日が除外日なら「スキップ」（連続日数にカウントしない）
  #   3. その日が達成済みなら streak + 1
  #   4. 未達成で rest_mode_on_date? が true なら「スキップ」（ストリーク維持）
  #   5. 未達成でお休みモードでもない → ストリーク終了
  def calculate_streak!(reference_date = HabitRecord.today_for_record)
    # ── Step 1: 過去90日分の達成記録を一括取得 ──────────────────────────
    #
    # なぜ一括取得するのか:
    #   ループの中で毎回 DB クエリを発行すると N+1 問題になる。
    #   90日分を1回のクエリで取得して Hash に変換し、
    #   ループ内では Hash の参照だけで完結させることで高速化する。
    #
    # pluck(:record_date, :completed, :numeric_value) とは:
    #   HabitRecord オブジェクト全体ではなく、
    #   必要な3カラムだけを配列で取得する Rails のメソッド。
    #   メモリ使用量を抑えられる。
    start_date  = reference_date - 90.days
    records_map = habit_records
                    .where(record_date: start_date..reference_date, deleted_at: nil)
                    .pluck(:record_date, :completed, :numeric_value)
                    .each_with_object({}) do |(date, completed, numeric_value), hash|
                      # { 日付 => 達成したか(boolean) } のハッシュを作る
                      #
                      # 【修正】numeric_value の判定を present? && > 0 に変更
                      # 修正前: numeric_value.to_f > 0
                      #   → nil.to_f が 0.0 になるため、
                      #     「未入力(nil)」と「0入力」の区別がつかなかった。
                      # 修正後: numeric_value.present? && numeric_value > 0
                      #   → nil と 0 を明示的に区別して判定する。
                      #   present? は nil と空文字を false にするため、
                      #   nil（未入力）の場合は false（未達成）として扱える。
                      hash[date] = if check_type?
                                     completed
                                   else
                                     numeric_value.present? && numeric_value > 0
                                   end
                    end

    # ── Step 2: 除外日番号をセットに変換 ────────────────────────────────
    #
    # Set を使う理由:
    #   Array#include? は O(n) だが Set#include? は O(1) でより高速。
    excluded_days_set = Set.new(excluded_day_numbers)

    # ── Step 3: 過去に向かってループしてストリークを計算 ─────────────────
    streak = 0

    (0..90).each do |days_ago|
      date        = reference_date - days_ago
      day_of_week = date.wday  # 0=日曜, 1=月曜, ..., 6=土曜

      # ── 除外日の処理 ──────────────────────────────────────────────────
      # 除外日はスキップする（ストリークを壊さないし、増やさない）
      next if excluded_days_set.include?(day_of_week)

      achieved = records_map[date]

      if achieved
        streak += 1
      else
        # ── お休みモードの処理（修正版）────────────────────────────────
        # 【修正ポイント】
        #   修正前: on_rest_mode? → 「今この瞬間」の状態で判定していた
        #           → 昨日はお休みモード中だったが今日は終了している場合に
        #             誤って「お休みモード外」と判定してしまうバグがあった。
        #   修正後: rest_mode_on_date?(date) → 「その日（date）の時点」で判定する
        #           → 過去の日付に対しても正しくお休みモードを適用できる。
        if rest_mode_on_date?(date)
          # お休みモードが有効な日はスキップ（ストリークを維持）
          next
        end

        # 未達成でお休みモードでもない → ストリーク終了
        break
      end
    end

    # ── Step 4: habits テーブルを更新 ────────────────────────────────────
    #
    # longest_streak の保護:
    #   現在の longest_streak より streak が大きい場合のみ更新する。
    #   「最高記録は絶対に下がらない」という仕様を守る。
    new_longest = [ longest_streak, streak ].max

    # update_columns を使う理由:
    #   ① バリデーションをスキップして高速に更新できる
    #   ② updated_at を更新しない
    #   ③ last_streak_calculated_at で最後の計算時刻を記録する
    update_columns(
      current_streak:            streak,
      longest_streak:            new_longest,
      last_streak_calculated_at: Time.current
    )

    streak
  end

  # ============================================================
  # 進捗統計メソッド（既存）
  # ============================================================

  def weekly_progress_stats(user)
    range = current_week_range

    if check_type?
      target = effective_weekly_target
      return { rate: 0, completed_count: 0, numeric_sum: nil, effective_target: target } if target.zero?

      completed_count = habit_records
                          .where(user: user, record_date: range, completed: true)
                          .count
      rate = ((completed_count.to_f / target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: completed_count, numeric_sum: nil, effective_target: target }
    else
      return { rate: 0, completed_count: nil, numeric_sum: 0.0, effective_target: weekly_target } if weekly_target.zero?

      numeric_sum   = habit_records
                        .where(user: user, record_date: range, deleted_at: nil)
                        .sum(:numeric_value)
      numeric_sum_f = numeric_sum.to_f
      rate          = ((numeric_sum_f / weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: nil, numeric_sum: numeric_sum_f, effective_target: weekly_target }
    end
  end

  # ============================================================
  # private
  # ============================================================
  private

  def current_week_range
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_start..today
  end
end