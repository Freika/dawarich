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

ActiveRecord::Schema[8.1].define(version: 2026_07_20_170000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "postgis"

  create_table "achievement_progresses", force: :cascade do |t|
    t.string "achievement_key", null: false
    t.datetime "created_at", null: false
    t.boolean "sharing_enabled", default: false, null: false
    t.string "sharing_uuid"
    t.jsonb "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["sharing_uuid"], name: "index_achievement_progresses_on_sharing_uuid", unique: true
    t.index ["user_id", "achievement_key"], name: "index_achievement_progresses_on_user_id_and_achievement_key", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "areas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.string "name", null: false
    t.integer "radius", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_areas_on_user_id"
  end

  create_table "countries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.geometry "geom", limit: {srid: 4326, type: "multi_polygon"}
    t.string "iso_a2", null: false
    t.string "iso_a3", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["geom"], name: "index_countries_on_geom", using: :gist
    t.index ["iso_a2"], name: "index_countries_on_iso_a2"
    t.index ["iso_a3"], name: "index_countries_on_iso_a3"
    t.index ["name"], name: "index_countries_on_name"
  end

  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "digests", force: :cascade do |t|
    t.jsonb "all_time_stats", default: {}
    t.datetime "created_at", null: false
    t.bigint "distance", default: 0, null: false
    t.jsonb "first_time_visits", default: {}
    t.integer "month"
    t.jsonb "monthly_distances", default: {}
    t.integer "period_type", default: 0, null: false
    t.datetime "sent_at"
    t.jsonb "sharing_settings", default: {}
    t.uuid "sharing_uuid"
    t.jsonb "time_spent_by_location", default: {}
    t.jsonb "toponyms", default: {}
    t.jsonb "travel_patterns", default: {}
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", null: false
    t.jsonb "year_over_year", default: {}
    t.index ["period_type"], name: "index_digests_on_period_type"
    t.index ["sharing_uuid"], name: "index_digests_on_sharing_uuid", unique: true
    t.index ["user_id", "year", "month", "period_type"], name: "index_digests_on_user_year_month_period_type", unique: true
    t.index ["user_id", "year", "period_type"], name: "index_digests_on_user_year_period_type_monthless", unique: true, where: "(month IS NULL)"
    t.index ["user_id"], name: "index_digests_on_user_id"
    t.index ["year"], name: "index_digests_on_year"
  end

  create_table "exports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_at"
    t.text "error_message"
    t.integer "file_format", default: 0
    t.integer "file_type", default: 0, null: false
    t.string "name", null: false
    t.datetime "processing_started_at"
    t.datetime "start_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id", null: false
    t.index ["file_type"], name: "index_exports_on_file_type"
    t.index ["status"], name: "index_exports_on_status"
    t.index ["user_id"], name: "index_exports_on_user_id"
  end

  create_table "families", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.string "name", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_families_on_creator_id"
  end

  create_table "family_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "family_id", null: false
    t.bigint "invited_by_id", null: false
    t.integer "status", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id", "email"], name: "index_family_invitations_on_family_id_and_email"
    t.index ["family_id", "status", "expires_at"], name: "index_family_invitations_on_family_status_expires"
    t.index ["status", "expires_at"], name: "index_family_invitations_on_status_and_expires_at"
    t.index ["status", "updated_at"], name: "index_family_invitations_on_status_and_updated_at"
    t.index ["token"], name: "index_family_invitations_on_token", unique: true
  end

  create_table "family_location_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "family_id", null: false
    t.bigint "requester_id", null: false
    t.datetime "responded_at"
    t.integer "status", default: 0, null: false
    t.string "suggested_duration", default: "24h", null: false
    t.bigint "target_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at", "status"], name: "idx_family_loc_requests_expires_status"
    t.index ["family_id"], name: "index_family_location_requests_on_family_id"
    t.index ["requester_id", "target_user_id", "status"], name: "idx_family_loc_requests_requester_target_status"
    t.index ["target_user_id", "status"], name: "idx_family_loc_requests_target_status"
  end

  create_table "family_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "family_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["family_id", "role"], name: "index_family_memberships_on_family_and_role"
    t.index ["user_id"], name: "index_family_memberships_on_user_id", unique: true
  end

  create_table "flights", force: :cascade do |t|
    t.string "aircraft_name"
    t.string "aircraft_reg"
    t.string "airline_iata"
    t.string "airline_name"
    t.datetime "arrival_time"
    t.datetime "created_at", null: false
    t.string "date_precision", default: "day", null: false
    t.datetime "departure_time"
    t.float "distance_km"
    t.integer "external_id", null: false
    t.date "flight_date"
    t.string "flight_number"
    t.string "from_code"
    t.float "from_lat"
    t.float "from_lon"
    t.string "from_name"
    t.text "note"
    t.jsonb "raw", default: {}, null: false
    t.string "seat"
    t.string "seat_class"
    t.string "to_code"
    t.float "to_lat"
    t.float "to_lon"
    t.string "to_name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "departure_time"], name: "index_flights_on_user_id_and_departure_time"
    t.index ["user_id", "external_id"], name: "index_flights_on_user_id_and_external_id", unique: true
    t.index ["user_id"], name: "index_flights_on_user_id"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.integer "doubles", default: 0
    t.text "error_message"
    t.string "name", null: false
    t.integer "points_count", default: 0
    t.integer "processed", default: 0
    t.datetime "processing_started_at"
    t.jsonb "raw_data"
    t.integer "raw_points", default: 0
    t.integer "source"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["source"], name: "index_imports_on_source"
    t.index ["status"], name: "index_imports_on_status"
    t.index ["user_id"], name: "index_imports_on_user_id"
  end

  create_table "notes", force: :cascade do |t|
    t.bigint "attachable_id"
    t.string "attachable_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.datetime "noted_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "attachable_type, attachable_id, ((noted_at)::date)", name: "index_notes_on_attachable_and_noted_date", unique: true, where: "(attachable_id IS NOT NULL)"
    t.index ["attachable_type", "attachable_id"], name: "index_notes_on_attachable_type_and_attachable_id"
    t.index ["lonlat"], name: "index_notes_on_lonlat", using: :gist
    t.index ["user_id", "noted_at"], name: "index_notes_on_user_id_and_noted_at"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["kind"], name: "index_notifications_on_kind"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "pending_imports", force: :cascade do |t|
    t.uuid "claim_ticket", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "claimed_at"
    t.bigint "claimed_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "origin", null: false
    t.string "original_filename", null: false
    t.string "source_hint"
    t.datetime "updated_at", null: false
    t.index ["claim_ticket"], name: "index_pending_imports_on_claim_ticket", unique: true
    t.index ["claimed_by_user_id"], name: "index_pending_imports_on_claimed_by_user_id"
    t.index ["expires_at"], name: "index_pending_imports_on_expires_at"
  end

  create_table "place_visits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "place_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "visit_id", null: false
    t.index ["place_id"], name: "index_place_visits_on_place_id"
    t.index ["visit_id", "place_id"], name: "idx_place_visits_visit_id_place_id", unique: true
  end

  create_table "places", force: :cascade do |t|
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.jsonb "geodata", default: {}, null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.string "name", null: false
    t.text "note"
    t.datetime "reverse_geocoded_at"
    t.integer "source", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index "(((geodata -> 'properties'::text) ->> 'osm_id'::text))", name: "index_places_on_geodata_osm_id"
    t.index ["demo"], name: "index_places_on_demo_true", where: "(demo = true)"
    t.index ["lonlat"], name: "index_places_on_lonlat", using: :gist
    t.index ["user_id"], name: "index_places_on_user_id"
  end

  create_table "points", force: :cascade do |t|
    t.integer "accuracy"
    t.integer "altitude"
    t.decimal "altitude_decimal", precision: 10, scale: 2
    t.boolean "anomaly"
    t.integer "battery"
    t.integer "battery_status"
    t.string "bssid"
    t.string "city"
    t.integer "connection"
    t.string "country"
    t.bigint "country_id"
    t.string "country_name"
    t.decimal "course", precision: 8, scale: 5
    t.decimal "course_accuracy", precision: 8, scale: 5
    t.datetime "created_at", null: false
    t.string "external_track_id"
    t.jsonb "geodata", default: {}, null: false
    t.bigint "import_id"
    t.text "in_regions", default: [], array: true
    t.text "inrids", default: [], array: true
    t.geography "lonlat", limit: {srid: 4326, type: "st_point", geographic: true}
    t.integer "mode"
    t.jsonb "motion_data", default: {}, null: false
    t.string "ping"
    t.jsonb "raw_data", default: {}
    t.bigint "raw_data_archive_id"
    t.boolean "raw_data_archived", default: false, null: false
    t.datetime "reverse_geocoded_at"
    t.string "ssid"
    t.integer "timestamp"
    t.string "topic"
    t.bigint "track_id"
    t.string "tracker_id"
    t.integer "trigger"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "velocity"
    t.integer "vertical_accuracy"
    t.bigint "visit_id"
    t.index ["id"], name: "index_points_on_not_reverse_geocoded", where: "(reverse_geocoded_at IS NULL)"
    t.index ["import_id"], name: "index_points_on_import_id"
    t.index ["lonlat", "timestamp", "user_id"], name: "index_points_on_lonlat_timestamp_user_id", unique: true
    t.index ["lonlat"], name: "index_points_on_lonlat", using: :gist
    t.index ["raw_data_archive_id"], name: "index_points_on_raw_data_archive_id"
    t.index ["track_id", "timestamp"], name: "idx_points_track_id_timestamp"
    t.index ["track_id"], name: "index_points_on_track_id"
    t.index ["user_id", "country_name"], name: "idx_points_user_country_name"
    t.index ["user_id", "geodata"], name: "index_points_on_user_id_and_empty_geodata", where: "(geodata = '{}'::jsonb)"
    t.index ["user_id", "id"], name: "index_points_on_unarchived", where: "((raw_data_archived = false) AND (raw_data <> '{}'::jsonb))"
    t.index ["user_id", "timestamp"], name: "idx_points_user_visit_null_timestamp", where: "(visit_id IS NULL)"
    t.index ["user_id", "timestamp"], name: "index_points_on_user_id_and_timestamp", order: { timestamp: :desc }
    t.index ["user_id"], name: "idx_points_user_id_legacy_tracker", where: "((tracker_id)::text = ANY (ARRAY[('google-maps-timeline-export'::character varying)::text, ('google-maps-phone-timeline-export'::character varying)::text]))"
    t.index ["user_id"], name: "index_points_on_user_id"
    t.index ["visit_id"], name: "index_points_on_visit_id"
  end

  create_table "points_raw_data_archives", force: :cascade do |t|
    t.datetime "archived_at", null: false
    t.integer "chunk_number", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "month", null: false
    t.integer "point_count", null: false
    t.string "point_ids_checksum", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "verified_at"
    t.integer "year", null: false
    t.index ["archived_at"], name: "index_points_raw_data_archives_on_archived_at"
    t.index ["user_id", "year", "month", "chunk_number"], name: "index_raw_data_archives_uniqueness", unique: true
    t.index ["user_id", "year", "month"], name: "index_points_raw_data_archives_on_user_id_and_year_and_month"
    t.index ["user_id"], name: "index_points_raw_data_archives_on_user_id"
  end

  create_table "posters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_posters_on_user_id"
  end

  create_table "regions", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.geometry "geom", limit: {srid: 4326, type: "multi_polygon"}, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_regions_on_code", unique: true
    t.index ["geom"], name: "index_regions_on_geom", using: :gist
  end

  create_table "shared_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_accessed_at"
    t.string "magic_phrase", limit: 255
    t.string "name", limit: 255, null: false
    t.bigint "resource_id"
    t.integer "resource_type", null: false
    t.datetime "revoked_at"
    t.jsonb "settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "view_count", default: 0, null: false
    t.index ["resource_type", "resource_id"], name: "index_shared_links_on_resource_type_and_resource_id", where: "(resource_id IS NOT NULL)"
    t.index ["user_id"], name: "index_shared_links_active_by_user", where: "(revoked_at IS NULL)"
    t.index ["user_id"], name: "index_shared_links_on_user_id"
  end

  create_table "stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "daily_distance", default: {}
    t.bigint "distance", null: false
    t.jsonb "h3_hex_ids", default: {}
    t.integer "month", null: false
    t.jsonb "sharing_settings", default: {}
    t.uuid "sharing_uuid"
    t.jsonb "toponyms"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", null: false
    t.index ["distance"], name: "index_stats_on_distance"
    t.index ["h3_hex_ids"], name: "index_stats_on_h3_hex_ids", where: "((h3_hex_ids IS NOT NULL) AND (h3_hex_ids <> '{}'::jsonb))", using: :gin
    t.index ["month"], name: "index_stats_on_month"
    t.index ["sharing_uuid"], name: "index_stats_on_sharing_uuid", unique: true
    t.index ["user_id", "year", "month"], name: "index_stats_on_user_id_year_month", unique: true
    t.index ["user_id"], name: "index_stats_on_user_id"
    t.index ["year"], name: "index_stats_on_year"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id", "tag_id"], name: "index_taggings_on_taggable_and_tag", unique: true
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.string "icon"
    t.string "name", null: false
    t.integer "privacy_radius_meters"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["demo"], name: "index_tags_on_demo_true", where: "(demo = true)"
    t.index ["privacy_radius_meters"], name: "index_tags_on_privacy_radius_meters", where: "(privacy_radius_meters IS NOT NULL)"
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "track_segments", force: :cascade do |t|
    t.float "avg_acceleration"
    t.float "avg_speed"
    t.integer "confidence", default: 0
    t.datetime "corrected_at"
    t.datetime "created_at", null: false
    t.integer "distance"
    t.integer "duration"
    t.integer "end_index", null: false
    t.float "max_speed"
    t.string "source"
    t.integer "start_index", null: false
    t.bigint "track_id", null: false
    t.integer "transportation_mode", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["corrected_at"], name: "index_track_segments_on_corrected_at", where: "(corrected_at IS NOT NULL)"
    t.index ["track_id", "start_index", "end_index"], name: "index_track_segments_on_track_and_indices"
    t.index ["track_id", "transportation_mode"], name: "index_track_segments_on_track_id_and_transportation_mode"
  end

  create_table "tracks", force: :cascade do |t|
    t.float "avg_speed"
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.bigint "distance"
    t.integer "dominant_mode", default: 0
    t.integer "duration"
    t.integer "elevation_gain"
    t.integer "elevation_loss"
    t.integer "elevation_max"
    t.integer "elevation_min"
    t.datetime "end_at", null: false
    t.geometry "original_path", limit: {srid: 4326, type: "line_string"}, null: false
    t.datetime "start_at", null: false
    t.string "tracker_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "user_id, COALESCE(tracker_id, ''::character varying), start_at, end_at", name: "index_tracks_on_user_tracker_start_end_unique", unique: true
    t.index ["demo"], name: "index_tracks_on_demo_true", where: "(demo = true)"
    t.index ["dominant_mode"], name: "index_tracks_on_dominant_mode"
    t.index ["user_id", "start_at"], name: "idx_tracks_user_id_start_at"
    t.index ["user_id", "tracker_id", "end_at"], name: "idx_tracks_user_tracker_end_at"
    t.index ["user_id"], name: "index_tracks_on_user_id"
  end

  create_table "trips", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.integer "distance"
    t.datetime "ended_at", null: false
    t.datetime "last_recalculated_at"
    t.string "name", null: false
    t.geometry "path", limit: {srid: 4326, type: "line_string"}
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "visited_countries", default: {}, null: false
    t.index ["demo"], name: "index_trips_on_demo_true", where: "(demo = true)"
    t.index ["user_id"], name: "index_trips_on_user_id"
  end

  create_table "user_achievements", force: :cascade do |t|
    t.string "achievement_key", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "achievement_key"], name: "index_user_achievements_on_user_id_and_achievement_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "active_until"
    t.boolean "admin", default: false
    t.string "api_key", default: "", null: false
    t.integer "changelog_consent"
    t.integer "consumed_timestep"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.datetime "deleted_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.integer "failed_otp_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.text "otp_backup_codes", array: true
    t.datetime "otp_locked_at"
    t.boolean "otp_required_for_login", default: false, null: false
    t.string "otp_secret"
    t.integer "plan", default: 1, null: false
    t.integer "points_count", default: 0, null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.jsonb "settings", default: {"fog_of_war_meters" => "100", "meters_between_routes" => "1000", "minutes_between_routes" => "60"}
    t.integer "sign_in_count", default: 0, null: false
    t.string "signup_variant"
    t.integer "status", default: 0
    t.integer "subscription_source", default: 0, null: false
    t.string "theme", default: "dark", null: false
    t.string "uid"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.datetime "visits_redetected_at"
    t.index ["api_key"], name: "index_users_on_api_key"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["otp_locked_at"], name: "index_users_on_otp_locked_at_not_null", where: "(otp_locked_at IS NOT NULL)"
    t.index ["plan"], name: "index_users_on_plan"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid_present", unique: true, where: "((provider IS NOT NULL) AND (uid IS NOT NULL))"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["signup_variant"], name: "index_users_on_signup_variant_reverse_trial", where: "((signup_variant)::text = 'reverse_trial'::text)"
    t.index ["status"], name: "index_users_on_status"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["visits_redetected_at"], name: "index_users_on_visits_redetected_at"
  end

  add_check_constraint "users", "admin IS NOT NULL", name: "users_admin_null", validate: false

  create_table "visits", force: :cascade do |t|
    t.bigint "area_id"
    t.integer "confidence", limit: 2
    t.jsonb "confidence_breakdown", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "demo", default: false, null: false
    t.integer "duration", null: false
    t.datetime "ended_at", null: false
    t.string "name", null: false
    t.bigint "place_id"
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["area_id"], name: "index_visits_on_area_id"
    t.index ["demo"], name: "index_visits_on_demo_true", where: "(demo = true)"
    t.index ["place_id"], name: "index_visits_on_place_id"
    t.index ["started_at"], name: "index_visits_on_started_at"
    t.index ["user_id"], name: "index_visits_on_user_id"
  end

  add_foreign_key "achievement_progresses", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "areas", "users"
  add_foreign_key "digests", "users"
  add_foreign_key "families", "users", column: "creator_id"
  add_foreign_key "family_invitations", "families"
  add_foreign_key "family_invitations", "users", column: "invited_by_id"
  add_foreign_key "family_location_requests", "families"
  add_foreign_key "family_location_requests", "users", column: "requester_id"
  add_foreign_key "family_location_requests", "users", column: "target_user_id"
  add_foreign_key "family_memberships", "families"
  add_foreign_key "family_memberships", "users"
  add_foreign_key "flights", "users"
  add_foreign_key "notes", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "pending_imports", "users", column: "claimed_by_user_id", on_delete: :nullify
  add_foreign_key "place_visits", "places"
  add_foreign_key "place_visits", "visits"
  add_foreign_key "points", "points_raw_data_archives", column: "raw_data_archive_id", on_delete: :restrict
  add_foreign_key "points", "users"
  add_foreign_key "points", "visits"
  add_foreign_key "points_raw_data_archives", "users"
  add_foreign_key "posters", "users"
  add_foreign_key "shared_links", "users", on_delete: :cascade
  add_foreign_key "stats", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tags", "users"
  add_foreign_key "track_segments", "tracks"
  add_foreign_key "tracks", "users"
  add_foreign_key "trips", "users"
  add_foreign_key "user_achievements", "users"
  add_foreign_key "visits", "areas"
  add_foreign_key "visits", "places"
  add_foreign_key "visits", "users"
end
