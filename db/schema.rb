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

ActiveRecord::Schema[8.0].define(version: 2025_06_27_184017) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "areas", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.integer "radius", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_areas_on_user_id"
  end

  create_table "countries", force: :cascade do |t|
    t.string "name", null: false
    t.string "iso_a2", null: false
    t.string "iso_a3", null: false
    t.geometry "geom", limit: {srid: 4326, type: "multi_polygon"}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["geom"], name: "index_countries_on_geom", using: :gist
    t.index ["iso_a2"], name: "index_countries_on_iso_a2"
    t.index ["iso_a3"], name: "index_countries_on_iso_a3"
    t.index ["name"], name: "index_countries_on_name"
  end

  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "exports", force: :cascade do |t|
    t.string "name", null: false
    t.string "url"
    t.integer "status", default: 0, null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "file_format", default: 0
    t.datetime "start_at"
    t.datetime "end_at"
    t.integer "file_type", default: 0, null: false
    t.index ["file_type"], name: "index_exports_on_file_type"
    t.index ["status"], name: "index_exports_on_status"
    t.index ["user_id"], name: "index_exports_on_user_id"
  end

  create_table "imports", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.integer "source", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "raw_points", default: 0
    t.integer "doubles", default: 0
    t.integer "processed", default: 0
    t.jsonb "raw_data"
    t.integer "points_count", default: 0
    t.integer "status", default: 0, null: false
    t.index ["source"], name: "index_imports_on_source"
    t.index ["status"], name: "index_imports_on_status"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "title", null: false
    t.text "content", null: false
    t.bigint "user_id", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_notifications_on_kind"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "place_visits", force: :cascade do |t|
    t.bigint "place_id", null: false
    t.bigint "visit_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["place_id"], name: "index_place_visits_on_place_id"
    t.index ["visit_id"], name: "index_place_visits_on_visit_id"
  end

  create_table "places", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.string "city"
    t.string "country"
    t.integer "source", default: 0
    t.jsonb "geodata", default: {}, null: false
    t.datetime "reverse_geocoded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.index ["lonlat"], name: "index_places_on_lonlat", using: :gist
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
    t.bigint "user_id"
    t.jsonb "geodata", default: {}, null: false
    t.bigint "visit_id"
    t.datetime "reverse_geocoded_at"
    t.decimal "course", precision: 8, scale: 5
    t.decimal "course_accuracy", precision: 8, scale: 5
    t.string "external_track_id"
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.bigint "country_id"
    t.index ["altitude"], name: "index_points_on_altitude"
    t.index ["battery"], name: "index_points_on_battery"
    t.index ["battery_status"], name: "index_points_on_battery_status"
    t.index ["city"], name: "index_points_on_city"
    t.index ["connection"], name: "index_points_on_connection"
    t.index ["country"], name: "index_points_on_country"
    t.index ["country_id"], name: "index_points_on_country_id"
    t.index ["external_track_id"], name: "index_points_on_external_track_id"
    t.index ["geodata"], name: "index_points_on_geodata", using: :gin
    t.index ["import_id"], name: "index_points_on_import_id"
    t.index ["latitude", "longitude"], name: "index_points_on_latitude_and_longitude"
    t.index ["lonlat", "timestamp", "user_id"], name: "index_points_on_lonlat_timestamp_user_id", unique: true
    t.index ["lonlat"], name: "index_points_on_lonlat", using: :gist
    t.index ["reverse_geocoded_at"], name: "index_points_on_reverse_geocoded_at"
    t.index ["timestamp"], name: "index_points_on_timestamp"
    t.index ["trigger"], name: "index_points_on_trigger"
    t.index ["user_id"], name: "index_points_on_user_id"
    t.index ["visit_id"], name: "index_points_on_visit_id"
  end

  create_table "stats", force: :cascade do |t|
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "distance", null: false
    t.jsonb "toponyms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "daily_distance", default: {}
    t.index ["distance"], name: "index_stats_on_distance"
    t.index ["month"], name: "index_stats_on_month"
    t.index ["user_id"], name: "index_stats_on_user_id"
    t.index ["year"], name: "index_stats_on_year"
  end

  create_table "trips", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at", null: false
    t.integer "distance"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.geometry "path", limit: {srid: 3857, type: "line_string"}
    t.jsonb "visited_countries", default: {}, null: false
    t.index ["user_id"], name: "index_trips_on_user_id"
  end

  create_table "user_data_imports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "archive_file_name"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_user_data_imports_on_status"
    t.index ["user_id", "created_at"], name: "index_user_data_imports_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_user_data_imports_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "", null: false
    t.string "theme", default: "dark", null: false
    t.jsonb "settings", default: {"fog_of_war_meters" => "100", "meters_between_routes" => "1000", "minutes_between_routes" => "60"}
    t.boolean "admin", default: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "status", default: 0
    t.datetime "active_until"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_check_constraint "users", "admin IS NOT NULL", name: "users_admin_null", validate: false

  create_table "visits", force: :cascade do |t|
    t.bigint "area_id"
    t.bigint "user_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at", null: false
    t.integer "duration", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "place_id"
    t.index ["area_id"], name: "index_visits_on_area_id"
    t.index ["place_id"], name: "index_visits_on_place_id"
    t.index ["started_at"], name: "index_visits_on_started_at"
    t.index ["user_id"], name: "index_visits_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "areas", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "place_visits", "places"
  add_foreign_key "place_visits", "visits"
  add_foreign_key "points", "users"
  add_foreign_key "points", "visits"
  add_foreign_key "stats", "users"
  add_foreign_key "trips", "users"
  add_foreign_key "user_data_imports", "users"
  add_foreign_key "visits", "areas"
  add_foreign_key "visits", "places"
  add_foreign_key "visits", "users"
end
