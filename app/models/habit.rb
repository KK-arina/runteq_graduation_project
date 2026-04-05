# app/models/habit.rb
# （既存コードの acts_as_list 関連の追加・変更のみ）
# ==============================================================================
# Habit（習慣）モデル（B-6: カラー・アイコン・並び替え追加）
# ==============================================================================
#
# 【B-6 での変更内容】
#
#   ① acts_as_list :column => :position, :scope => :user_id を追加
#      理由:
#        habits テーブルの position カラムを使って習慣の表示順を管理する。
#        scope: :user_id を指定することで、ユーザーごとに独立した
#        連番（1, 2, 3...）が管理される。
#        スコープなしだと全ユーザーで1つの連番になり、
#        「他のユーザーの習慣追加」で自分の順番がずれてしまう。
#
#   ② scope :active の order を created_at から position に変更
#      理由: ユーザーが並び替えた順番を反映するため。
#            position が NULL の既存レコードは末尾に来るように
#            NULLS LAST を使う。
#
#   ③ color / icon バリデーションを追加
#      理由: 不正な値が DB に入らないように制約を設ける。
# ==============================================================================

class Habit < ApplicationRecord
  # ============================================================
  # acts_as_list（B-6 追加）
  # ============================================================
  # acts_as_list :column => :position
  #   habits テーブルの position カラムを「並び順」として使うことを宣言する。
  #   これにより以下のメソッドが自動で使えるようになる:
  #     habit.move_to_top      → position = 1 にする
  #     habit.move_to_bottom   → position = 最後にする
  #     habit.insert_at(n)     → position = n にする（他のレコードは自動でずれる）
  #
  # scope: :user_id
  #   「同じ user_id の習慣の中で」position を管理する。
  #   例: ユーザーAの習慣は 1, 2, 3...
  #       ユーザーBの習慣は別に 1, 2, 3...
  #   スコープなしだと全ユーザーで通し番号になり、
  #   他のユーザーが習慣を追加・削除するたびに自分の順番がずれる問題が起きる。
  #
  # add_new_at: :bottom
  #   新規作成した習慣をリストの末尾に追加する。
  #   デフォルトも :bottom だが明示することで意図を明確にする。
  acts_as_list column: :position, scope: :user_id, add_new_at: :bottom

  # ============================================================
  # アソシエーション（変更なし）
  # ============================================================
  belongs_to :user
  has_many :habit_records, dependent: :destroy
  has_many :weekly_reflection_habit_summaries, dependent: :nullify
  has_many :habit_excluded_days, dependent: :destroy

  # ============================================================
  # Enum 定義（変更なし）
  # ============================================================
  enum :measurement_type, {
    check_type:   0,
    numeric_type: 1
  }

  # ============================================================
  # バリデーション（B-6: color / icon を追加）
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

  # color バリデーション（B-6 追加）
  # 【理由】
  #   フォームから送られてくる color は "#3b82f6" のような CSS カラーコード。
  #   16進数カラーコードの形式（# + 6文字の英数字）以外の値が
  #   DB に入るのを防ぐ。
  #   allow_blank: true を使うのは、色を設定しない（デフォルト使用）場合も
  #   許容するため。
  validates :color,
            format: {
              with:    /\A#[0-9a-fA-F]{6}\z/,
              message: "は #rrggbb 形式で入力してください"
            },
            allow_blank: true

  # icon バリデーション（B-6 追加）
  # 【理由】
  #   icon は絵文字1文字を想定している。
  #   長さを1〜2文字（絵文字は内部的に複数コードポイントになる場合がある）
  #   に制限して、長い文字列が入らないようにする。
  validates :icon, length: { maximum: 2 }, allow_blank: true

  # ============================================================
  # スコープ（B-6: active の order を変更）
  # ============================================================

  # scope :active（B-6 変更）
  # 【変更前】where(deleted_at: nil, archived_at: nil)
  # 【変更後】where(deleted_at: nil, archived_at: nil).order(position: :asc, created_at: :asc)
  #
  # なぜ order を変更するのか:
  #   acts_as_list で管理する position の順に習慣を表示するため。
  #   ユーザーが並び替えた結果を反映させる。
  #
  # position: :asc
  #   position 1 → 2 → 3 の昇順。
  #
  # created_at: :asc（セカンダリーソート）
  #   position が同じ（NULL など）の場合の並び順を作成日時で統一する。
  #   Nils Last: PostgreSQL では NULL は昇順ソートで最後に来るため
  #   position が NULL の既存レコードは末尾に表示される。
  scope :active,   -> { where(deleted_at: nil, archived_at: nil).order(Arel.sql("position ASC NULLS LAST, created_at ASC")) }

  # その他のスコープ（変更なし）
  scope :archived, -> { where(deleted_at: nil).where.not(archived_at: nil) }
  scope :deleted,  -> { where.not(deleted_at: nil) }

  # ============================================================
  # インスタンスメソッド（変更なし）
  # ============================================================

  def soft_delete
    touch(:deleted_at)
  end

  def active?
    deleted_at.nil? && archived_at.nil?
  end

  def deleted?
    deleted_at.present?
  end

  def archived?
    archived_at.present?
  end

  def archive!
    raise RuntimeError, "すでにアーカイブ済みです" if archived?
    raise RuntimeError, "削除済みのため操作できません" if deleted?
    update!(archived_at: Time.current)
  end

  def unarchive!
    raise RuntimeError, "アーカイブされていません" unless archived?
    update!(archived_at: nil)
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
  # B-3 追加: ストリーク関連メソッド（変更なし）
  # ============================================================

  def on_rest_mode?
    user.user_setting&.rest_mode_active?
  end

  def rest_mode_on_date?(date)
    return false unless allow_rest_mode
    setting = user.user_setting
    return false unless setting
    return false unless setting.rest_mode_until.present?
    setting.rest_mode_until.to_date >= date
  end

  def calculate_streak!(reference_date = HabitRecord.today_for_record)
    start_date  = reference_date - 90.days
    records_map = habit_records
                    .where(record_date: start_date..reference_date, deleted_at: nil)
                    .pluck(:record_date, :completed, :numeric_value)
                    .each_with_object({}) do |(date, completed, numeric_value), hash|
                      hash[date] = if check_type?
                                     completed
                                   else
                                     numeric_value.present? && numeric_value > 0
                                   end
                    end

    excluded_days_set = Set.new(excluded_day_numbers)
    streak = 0

    (0..90).each do |days_ago|
      date        = reference_date - days_ago
      day_of_week = date.wday
      next if excluded_days_set.include?(day_of_week)
      achieved = records_map[date]
      if achieved
        streak += 1
      else
        break unless rest_mode_on_date?(date)
      end
    end

    new_longest = [ longest_streak, streak ].max
    update_columns(
      current_streak:            streak,
      longest_streak:            new_longest,
      last_streak_calculated_at: Time.current
    )
    streak
  end

  # ============================================================
  # 進捗統計メソッド（変更なし）
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

  private

  def current_week_range
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_start..today
  end
end