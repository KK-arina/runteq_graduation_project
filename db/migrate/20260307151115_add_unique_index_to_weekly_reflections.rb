class AddUniqueIndexToWeeklyReflections < ActiveRecord::Migration[7.2]
  def change
    add_index :weekly_reflections,
              [:user_id, :week_start_date],
              unique: true,
              name: "index_weekly_reflections_on_user_id_and_week_start_date",
              if_not_exists: true
  end
end
