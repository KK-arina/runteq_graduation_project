# ==============================================================================
# app/models/habit.rb（追記分）
# ==============================================================================
# 【追加内容】
#   weekly_achievement_rate: 今週の達成率（0〜100 の整数）を返すメソッド。
#   ビューから呼び出して、プログレスバーに使用する。
# ==============================================================================
class Habit < ApplicationRecord
  belongs_to :user
  has_many :habit_records, dependent: :destroy

  # ---------------------------------------------------------------------------
  # バリデーション（既存）
  # ---------------------------------------------------------------------------
  validates :name,          presence: true, length: { maximum: 50 }
  validates :weekly_target, presence: true,
                            numericality: {
                              only_integer:             true,
                              greater_than_or_equal_to: 1,
                              less_than_or_equal_to:    7
                            }

  # ---------------------------------------------------------------------------
  # スコープ（既存）
  # ---------------------------------------------------------------------------
  scope :active,  -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # ---------------------------------------------------------------------------
  # インスタンスメソッド（既存）
  # ---------------------------------------------------------------------------
  def soft_delete
    touch(:deleted_at)
  end

  def active?
    deleted_at.nil?
  end

  def deleted?
    !active?
  end

  # ===========================================================================
  # weekly_achievement_rate（新規追加）
  # ===========================================================================
  # 【役割】
  #   今週（月曜日〜今日）の達成率を整数（0〜100）で返す。
  #
  # 【週の計算について】
  #   Rails の beginning_of_week はデフォルトで月曜日を週の始まりとする。
  #   config/application.rb で config.beginning_of_week = :monday を設定済みの想定。
  #   設定されていない場合は :monday を明示的に指定する。
  #
  # 【AM 4:00 基準の today について】
  #   HabitRecord.today_for_record で AM 4:00 基準の「今日」を取得する。
  #   これにより深夜の活動も正しく集計される。
  #
  # 【戻り値】
  #   Integer (0〜100)
  #   例: 今週3日実施、目標7日 → (3 / 7.0 * 100).round = 43
  # ===========================================================================
  def weekly_achievement_rate
    # AM 4:00 基準の今日
    today = HabitRecord.today_for_record

    # 今週の開始日（月曜日）
    # beginning_of_week(:monday) で月曜日の 00:00:00 を返す
    week_start = today.beginning_of_week(:monday)

    # 今週の完了日数を数える
    # .count は SQL の COUNT を使うので、Ruby の配列に展開しない（効率的）
    completed_count = habit_records
                        .where(record_date: week_start..today)
                        .where(completed: true)
                        .count

    # 達成率を計算する
    # weekly_target が 0 だと ZeroDivisionError になるため guard を入れる
    return 0 if weekly_target.zero?

    # (completed_count / weekly_target.to_f * 100).round で整数%を返す
    # to_f で Float に変換しないと整数除算になる（例: 3/7 → 0）
    # [rate, 100].min で 100% を超えないようにキャップする
    rate = (completed_count.to_f / weekly_target * 100).round
    [rate, 100].min
  end
end