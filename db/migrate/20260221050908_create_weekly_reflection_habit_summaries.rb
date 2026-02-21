# db/migrate/YYYYMMDDHHMMSS_create_weekly_reflection_habit_summaries.rb

class CreateWeeklyReflectionHabitSummaries < ActiveRecord::Migration[7.2]
  def change
    create_table :weekly_reflection_habit_summaries do |t|

      # どの「週次振り返り」に属するか
      # null: false → 振り返り本体がないサマリーは存在を許しません
      # on_delete: :cascade → 振り返り本体が消えたら、このサマリーも一緒に消去します
      t.references :weekly_reflection,
                   null: false,
                   foreign_key: { on_delete: :cascade }

      # 元となった「習慣」はどれか
      # ──────────────────────────────────────────
      # 【重要】null: true にする理由
      # on_delete: :nullify を設定しているため、習慣が物理削除されると
      # DBが habit_id を NULL に書き換えようとします。
      # null: false（NULL禁止）のままだと、NULLを入れようとした瞬間に
      # DB制約エラーが発生してしまいます。
      #
      # スナップショット設計の目的は「過去の振り返りデータを守ること」なので、
      # habit_id が NULL になっても habit_name 等のコピーデータは残ります。
      # ──────────────────────────────────────────
      t.references :habit,
                   null: true,           # ← ここが重要（null: false から変更）
                   foreign_key: { on_delete: :nullify }

      # スナップショット（振り返り時点の値をコピー保存）
      t.string  :habit_name,    null: false
      t.integer :weekly_target, null: false

      # 実績データ
      t.integer :actual_count, null: false, default: 0
      # precision: 5, scale: 2 → 「100.00」まで格納できる桁数設定
      t.decimal :achievement_rate,
                precision: 5,
                scale: 2,
                null: false,
                default: 0.0

      t.timestamps
    end

    # 同じ振り返りに同じ習慣が重複保存されないようにUNIQUE制約をかけます
    # name を短縮しているのは PostgreSQL の識別子制限（63文字）を超えないためです
    add_index :weekly_reflection_habit_summaries,
              [:weekly_reflection_id, :habit_id],
              unique: true,
              name: 'idx_wr_habit_summaries_on_wr_id_and_habit_id'
  end
end