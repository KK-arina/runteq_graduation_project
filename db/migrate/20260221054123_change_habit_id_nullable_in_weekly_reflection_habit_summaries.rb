# db/migrate/YYYYMMDDHHMMSS_change_habit_id_nullable_in_weekly_reflection_habit_summaries.rb
#
# 【このマイグレーションの目的】
# weekly_reflection_habit_summaries.habit_id の NOT NULL 制約を外す。
#
# 【なぜ必要か？】
# on_delete: :nullify を設定しているため、habit が削除されると
# DB が habit_id を NULL に書き換えようとする。
# NOT NULL 制約のままだと PG::NotNullViolation エラーになる。
#
# スナップショット設計では habit が削除されても
# habit_name 等のコピーデータを残す必要があるため NULL を許容する。

class ChangeHabitIdNullableInWeeklyReflectionHabitSummaries < ActiveRecord::Migration[7.2]
  def change
    # habit_id の NOT NULL 制約を外す
    # 第3引数 true → NULL を許容する
    change_column_null :weekly_reflection_habit_summaries, :habit_id, true
  end
end
