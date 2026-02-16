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

ActiveRecord::Schema[7.2].define(version: 2026_02_16_141407) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "habit_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "habit_id", null: false
    t.date "record_date", null: false
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["habit_id"], name: "index_habit_records_on_habit_id"
    t.index ["user_id", "habit_id", "record_date"], name: "index_habit_records_on_user_habit_date", unique: true
    t.index ["user_id"], name: "index_habit_records_on_user_id"
  end

  create_table "habits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", limit: 50, null: false
    t.integer "weekly_target", default: 7, null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_habits_on_deleted_at"
    t.index ["user_id", "deleted_at"], name: "index_habits_on_user_id_and_deleted_at"
    t.index ["user_id"], name: "index_habits_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "habit_records", "habits", on_delete: :cascade
  add_foreign_key "habit_records", "users", on_delete: :cascade
  add_foreign_key "habits", "users"
end
