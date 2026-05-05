# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_05_05_094158) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "ai_analyses", force: :cascade do |t|
    t.bigint "weekly_reflection_id"
    t.bigint "user_purpose_id"
    t.integer "analysis_type", default: 0, null: false
    t.jsonb "input_snapshot"
    t.text "analysis_comment"
    t.text "improvement_suggestions"
    t.text "root_cause"
    t.text "coaching_message"
    t.jsonb "actions_json"
    t.boolean "crisis_detected", default: false, null: false
    t.string "prompt_version"
    t.string "ai_model_name"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_latest", default: true, null: false
    t.index ["analysis_type"], name: "index_ai_analyses_on_analysis_type"
    t.index ["is_latest"], name: "index_ai_analyses_on_is_latest_true", where: "(is_latest = true)"
    t.index ["user_purpose_id", "analysis_type"], name: "index_ai_analyses_latest_purpose_type_unique", unique: true, where: "((user_purpose_id IS NOT NULL) AND (is_latest = true))"
    t.index ["user_purpose_id"], name: "index_ai_analyses_on_user_purpose_id"
    t.index ["user_purpose_id"], name: "index_ai_analyses_on_user_purpose_id_fk"
    t.index ["weekly_reflection_id"], name: "index_ai_analyses_latest_weekly_reflection_unique", unique: true, where: "((weekly_reflection_id IS NOT NULL) AND (is_latest = true))"
    t.index ["weekly_reflection_id"], name: "index_ai_analyses_on_weekly_reflection_id"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "habit_excluded_days", force: :cascade do |t|
    t.bigint "habit_id", null: false
    t.integer "day_of_week", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["habit_id", "day_of_week"], name: "index_habit_excluded_days_on_habit_id_and_day_of_week", unique: true
    t.index ["habit_id"], name: "index_habit_excluded_days_on_habit_id"
  end

  create_table "habit_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "habit_id", null: false
    t.date "record_date", null: false
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "numeric_value", precision: 10, scale: 2
    t.text "memo"
    t.boolean "is_manual_input", default: false
    t.datetime "deleted_at"
    t.index ["habit_id", "deleted_at", "record_date"], name: "index_habit_records_on_habit_deleted_date"
    t.index ["habit_id"], name: "index_habit_records_on_habit_id"
    t.index ["user_id", "habit_id", "record_date"], name: "index_habit_records_on_user_habit_date", unique: true
    t.index ["user_id", "record_date"], name: "index_habit_records_on_user_id_and_record_date"
    t.index ["user_id"], name: "index_habit_records_on_user_id"
  end

  create_table "habit_templates", force: :cascade do |t|
    t.string "name", null: false
    t.integer "measurement_type", default: 0, null: false
    t.string "default_unit"
    t.integer "default_weekly_target", default: 5, null: false
    t.integer "category", default: 4, null: false
    t.text "description"
    t.integer "sort_order"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active", "sort_order"], name: "index_habit_templates_on_is_active_and_sort_order"
  end

  create_table "habits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", limit: 50, null: false
    t.integer "weekly_target", default: 7, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "unit"
    t.integer "measurement_type", default: 0, null: false
    t.integer "current_streak", default: 0, null: false
    t.integer "longest_streak", default: 0, null: false
    t.datetime "last_streak_calculated_at"
    t.boolean "allow_rest_mode", default: true, null: false
    t.datetime "archived_at"
    t.string "color"
    t.string "icon"
    t.integer "position"
    t.index ["deleted_at"], name: "index_habits_on_deleted_at"
    t.index ["user_id", "archived_at"], name: "index_habits_on_user_id_and_archived_at"
    t.index ["user_id", "deleted_at"], name: "index_habits_on_user_id_and_deleted_at"
    t.index ["user_id", "position"], name: "index_habits_on_user_id_and_position"
    t.index ["user_id"], name: "index_habits_on_user_id"
  end

  create_table "notification_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.integer "channel", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.string "deep_link_url"
    t.integer "status", default: 0, null: false
    t.text "error_message"
    t.integer "retry_count", default: 0, null: false
    t.jsonb "metadata"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_notification_logs_on_channel"
    t.index ["deep_link_url"], name: "index_notification_logs_on_deep_link_url"
    t.index ["notification_type"], name: "index_notification_logs_on_notification_type"
    t.index ["status"], name: "index_notification_logs_on_status_not_success", where: "(status <> 0)"
    t.index ["target_type", "target_id"], name: "index_notification_logs_on_target_type_and_target_id"
    t.index ["user_id", "created_at"], name: "index_notification_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notification_logs_on_user_id"
  end

  create_table "password_reset_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "expires_at", null: false
    t.boolean "is_used", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token_digest", null: false
    t.index ["token_digest"], name: "index_password_reset_tokens_on_token_digest_unique", unique: true
    t.index ["user_id"], name: "index_password_reset_tokens_on_user_id"
    t.index ["user_id"], name: "index_password_reset_tokens_on_user_id_unique", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "endpoint"
    t.string "p256dh"
    t.string "auth"
    t.string "device_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.text "channel", null: false
    t.text "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", default: 0, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "habit_id"
    t.string "title", null: false
    t.integer "priority", default: 1, null: false
    t.integer "task_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.date "due_date"
    t.decimal "estimated_hours", precision: 5, scale: 1
    t.datetime "scheduled_at"
    t.boolean "alarm_enabled", default: false, null: false
    t.integer "alarm_minutes_before"
    t.datetime "completed_at"
    t.boolean "ai_generated", default: false, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alarm_enabled", "scheduled_at"], name: "index_tasks_on_alarm_enabled_and_scheduled_at"
    t.index ["user_id", "alarm_enabled"], name: "index_tasks_on_user_id_and_alarm_enabled"
    t.index ["user_id", "scheduled_at"], name: "index_tasks_on_user_id_and_scheduled_at"
    t.index ["user_id", "status", "deleted_at", "due_date"], name: "idx_tasks_active_tasks", where: "(deleted_at IS NULL)"
    t.index ["user_id", "status", "due_date"], name: "index_tasks_on_user_id_and_status_and_due_date"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "user_purposes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "purpose"
    t.text "mission"
    t.text "vision"
    t.text "value"
    t.text "current_situation"
    t.integer "version", default: 1, null: false
    t.boolean "is_active", default: true, null: false
    t.integer "analysis_state", default: 0, null: false
    t.text "last_error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "is_active"], name: "index_user_purposes_on_user_id_and_is_active"
    t.index ["user_id"], name: "index_user_purposes_on_user_id"
  end

  create_table "user_settings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "time_zone", default: "Asia/Tokyo"
    t.boolean "notification_enabled", default: true, null: false
    t.boolean "line_notification_enabled", default: false, null: false
    t.boolean "email_notification_enabled", default: true, null: false
    t.integer "daily_notification_limit", default: 5, null: false
    t.integer "daily_notification_count", default: 0, null: false
    t.datetime "notification_count_reset_at"
    t.datetime "last_notification_sent_at"
    t.boolean "weekly_report_enabled", default: true, null: false
    t.datetime "rest_mode_until"
    t.string "rest_mode_reason"
    t.integer "ai_analysis_count", default: 0, null: false
    t.integer "ai_analysis_monthly_limit", default: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_ai_requested_at", comment: "最後にAI分析リクエストを受け付けた日時。D-10レート制限で使用。"
    t.index ["user_id"], name: "index_user_settings_on_user_id"
    t.index ["user_id"], name: "index_user_settings_on_user_id_unique", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", default: "email"
    t.string "uid"
    t.string "line_user_id"
    t.datetime "first_login_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  create_table "weekly_reflection_habit_summaries", force: :cascade do |t|
    t.bigint "weekly_reflection_id", null: false
    t.bigint "habit_id"
    t.string "habit_name", null: false
    t.integer "weekly_target", null: false
    t.integer "actual_count", default: 0, null: false
    t.decimal "achievement_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["habit_id"], name: "index_weekly_reflection_habit_summaries_on_habit_id"
    t.index ["weekly_reflection_id", "habit_id"], name: "idx_wr_habit_summaries_on_wr_id_and_habit_id", unique: true
    t.index ["weekly_reflection_id"], name: "idx_on_weekly_reflection_id_641bf747c5"
  end

  create_table "weekly_reflection_task_summaries", force: :cascade do |t|
    t.bigint "weekly_reflection_id", null: false
    t.bigint "task_id"
    t.string "title", null: false
    t.integer "priority", default: 1, null: false
    t.integer "task_type", default: 0, null: false
    t.boolean "was_completed", default: false, null: false
    t.datetime "completed_at"
    t.date "due_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_weekly_reflection_task_summaries_on_task_id"
    t.index ["weekly_reflection_id", "task_id"], name: "idx_wr_task_summaries_on_wr_id_and_task_id", unique: true, where: "(task_id IS NOT NULL)"
    t.index ["weekly_reflection_id"], name: "index_weekly_reflection_task_summaries_on_weekly_reflection_id"
  end

  create_table "weekly_reflections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "week_start_date", null: false
    t.date "week_end_date", null: false
    t.text "reflection_comment"
    t.boolean "is_locked", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.integer "year"
    t.integer "week_number"
    t.integer "mood"
    t.text "direct_reason"
    t.text "background_situation"
    t.text "next_action"
    t.index ["user_id", "week_start_date", "completed_at"], name: "idx_weekly_reflections_user_week_completed", where: "(completed_at IS NOT NULL)"
    t.index ["user_id", "week_start_date"], name: "index_weekly_reflections_on_user_id_and_week_start_date", unique: true
    t.index ["user_id", "year", "week_number"], name: "index_weekly_reflections_on_user_year_week", unique: true
    t.index ["user_id"], name: "index_weekly_reflections_on_user_id"
  end

  add_foreign_key "ai_analyses", "user_purposes", on_delete: :cascade
  add_foreign_key "ai_analyses", "weekly_reflections", on_delete: :cascade
  add_foreign_key "habit_excluded_days", "habits", on_delete: :cascade
  add_foreign_key "habit_records", "habits", on_delete: :cascade
  add_foreign_key "habit_records", "users", on_delete: :cascade
  add_foreign_key "habits", "users"
  add_foreign_key "notification_logs", "users", on_delete: :cascade
  add_foreign_key "password_reset_tokens", "users", on_delete: :cascade
  add_foreign_key "push_subscriptions", "users", on_delete: :cascade
  add_foreign_key "tasks", "habits", on_delete: :nullify
  add_foreign_key "tasks", "users", on_delete: :cascade
  add_foreign_key "user_purposes", "users", on_delete: :cascade
  add_foreign_key "user_settings", "users", on_delete: :cascade
  add_foreign_key "weekly_reflection_habit_summaries", "habits", on_delete: :nullify
  add_foreign_key "weekly_reflection_habit_summaries", "weekly_reflections", on_delete: :cascade
  add_foreign_key "weekly_reflection_task_summaries", "tasks", on_delete: :nullify
  add_foreign_key "weekly_reflection_task_summaries", "weekly_reflections", on_delete: :cascade
  add_foreign_key "weekly_reflections", "users", on_delete: :cascade
end
