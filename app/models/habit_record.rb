# app/models/habit_record.rb
#
# ==============================================================================
# 【テスト失敗修正】
#
#   find_or_create_for を数値型対応に修正する。
#
#   【問題の根本原因】
#     find_or_create_by!(user:, habit:, record_date:) で新規作成するとき、
#     numeric_value を指定していないため nil になる。
#     数値型習慣では numeric_value_required_for_numeric_type バリデーションが
#     nil を弾くためエラーになっていた。
#
#   【修正方法】
#     数値型習慣のとき: create_with(numeric_value: 0.0, completed: false) を追加。
#     チェック型習慣のとき: 従来通り。
#     create_with は「新規作成時だけ」適用される。
#     既存レコードが見つかった場合は create_with の値は無視される。
# ==============================================================================

class HabitRecord < ApplicationRecord
  belongs_to :user
  belongs_to :habit

  validates :record_date, presence: true
  validates :record_date, uniqueness: { scope: [ :user_id, :habit_id ] }
  validates :completed, inclusion: { in: [ true, false ] }

  validates :numeric_value,
            numericality: {
              greater_than_or_equal_to: 0,
              message: "は0以上の数値を入力してください"
            },
            allow_nil: true

  validate :numeric_value_required_for_numeric_type

  scope :for_date,          ->(date) { where(record_date: date) }
  scope :for_user,          ->(user) { where(user: user) }
  scope :completed_records, ->       { where(completed: true) }

  def self.today_for_record
    now      = Time.current
    boundary = now.change(hour: 4, min: 0, sec: 0)
    now < boundary ? now.to_date - 1.day : now.to_date
  end

  # find_or_create_for（数値型対応版）
  # 【修正内容】
  #   数値型習慣の場合は create_with(numeric_value: 0.0, completed: false) を
  #   チェーンすることで、新規作成時のみ初期値をセットする。
  #   これにより numeric_value_required_for_numeric_type バリデーションを通過できる。
  #
  # 【なぜ create_with を使うのか】
  #   find_or_create_by! に直接 numeric_value: 0.0 を渡すと
  #   「検索条件」にも含まれてしまい、値が変わったときに別レコードを作成してしまう。
  #   create_with は「作成時だけ」適用されるため、検索条件には含まれない。
  def self.find_or_create_for(user, habit, date = today_for_record)
    if habit.numeric_type?
      # 数値型: 新規作成時に numeric_value: 0.0 / completed: false を初期値にセット
      create_with(numeric_value: 0.0, completed: false)
        .find_or_create_by!(user: user, habit: habit, record_date: date)
    else
      # チェック型: 従来通り（completed はデフォルト false で問題なし）
      find_or_create_by!(user: user, habit: habit, record_date: date)
    end
  end

  def update_completed!(value)
    update!(completed: value)
  end

  def toggle_completed!
    toggle!(:completed)
  end

  def update_numeric_value!(value)
    update!(numeric_value: value)
  end

  private

  def numeric_value_required_for_numeric_type
    return unless habit.present? && habit.numeric_type?
    return unless numeric_value.nil?
    errors.add(:numeric_value, "を入力してください（数値型習慣では必須です）")
  end
end
