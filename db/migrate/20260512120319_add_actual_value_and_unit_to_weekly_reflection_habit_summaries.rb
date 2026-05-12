# db/migrate/YYYYMMDDHHMMSS_add_actual_value_and_unit_to_weekly_reflection_habit_summaries.rb
#
# ==============================================================================
# 【マイグレーションの目的】
#   weekly_reflection_habit_summaries テーブルに数値型習慣対応のカラムを追加する。
#
# 【追加カラムの説明】
#
#   actual_value (decimal, precision: 10, scale: 2, nullable)
#     数値型習慣の「実績値の合計（SUM）」を保存するカラム。
#     例: ジョギング 90分 → actual_value = 90.00
#     チェック型習慣では NULL を保存する（actual_count を使う）。
#     nullable にする理由:
#       チェック型の場合は actual_value が不要なため NULL を許容する。
#       NOT NULL にすると既存のチェック型データが全てデフォルト値を持つ必要があり
#       意味論的に正しくない（0.0 と「記録なし」を区別できなくなる）。
#
#   unit (string, nullable)
#     数値型習慣の「単位スナップショット」を保存するカラム。
#     例: "分", "冊", "km"
#     振り返り保存時点の unit を記録することで、
#     後から習慣の単位を変更しても過去の振り返りは正しく表示される
#     （スナップショット設計と同じ考え方）。
#     nullable にする理由:
#       チェック型習慣には unit がないため NULL を許容する。
#
# 【既存データへの影響】
#   add_column は既存レコードに NULL を追加するだけなので
#   データ損失・既存機能への影響はない。
# ==============================================================================
class AddActualValueAndUnitToWeeklyReflectionHabitSummaries < ActiveRecord::Migration[7.2]
  def change
    # actual_value カラムを追加する
    # precision: 10 → 整数部8桁 + 小数部2桁 = 最大10桁
    # scale: 2      → 小数点以下2桁（例: 90.50）
    # null: true（デフォルト）→ チェック型は NULL を保存するため nullable にする
    add_column :weekly_reflection_habit_summaries, :actual_value, :decimal,
               precision: 10, scale: 2, comment: "数値型習慣の週次実績値合計（SUM）。チェック型はNULL。"

    # unit カラムを追加する
    # string 型: "分", "冊", "km" などの短い文字列を想定
    # null: true（デフォルト）→ チェック型は NULL を保存するため nullable にする
    add_column :weekly_reflection_habit_summaries, :unit, :string,
               comment: "数値型習慣の単位スナップショット（例: 分, 冊）。チェック型はNULL。"
  end
end