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

ActiveRecord::Schema[7.1].define(version: 2024_03_23_125126) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "imports", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.integer "source", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "raw_points", default: 0
    t.integer "doubles", default: 0
    t.index ["source"], name: "index_imports_on_source"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "points", force: :cascade do |t|
    t.integer "battery_status"
    t.string "ping"
    t.integer "battery"
    t.string "tracker_id"
    t.string "topic"
    t.integer "altitude"
    t.decimal "longitude", precision: 10, scale: 6
    t.string "velocity"
    t.integer "trigger"
    t.string "bssid"
    t.string "ssid"
    t.integer "connection"
    t.integer "vertical_accuracy"
    t.integer "accuracy"
    t.integer "timestamp"
    t.decimal "latitude", precision: 10, scale: 6
    t.integer "mode"
    t.text "inrids", default: [], array: true
    t.text "in_regions", default: [], array: true
    t.jsonb "raw_data", default: {}
    t.bigint "import_id"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["altitude"], name: "index_points_on_altitude"
    t.index ["battery"], name: "index_points_on_battery"
    t.index ["battery_status"], name: "index_points_on_battery_status"
    t.index ["city"], name: "index_points_on_city"
    t.index ["connection"], name: "index_points_on_connection"
    t.index ["country"], name: "index_points_on_country"
    t.index ["import_id"], name: "index_points_on_import_id"
    t.index ["latitude", "longitude"], name: "index_points_on_latitude_and_longitude"
    t.index ["trigger"], name: "index_points_on_trigger"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
