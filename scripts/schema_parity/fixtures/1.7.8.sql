ALTER TABLE "users" ADD "failed_otp_attempts" integer DEFAULT 0 NOT NULL;
ALTER TABLE "users" ADD "otp_locked_at" timestamp(6);
CREATE INDEX "index_users_on_otp_locked_at_not_null" ON "users" ("otp_locked_at") WHERE otp_locked_at IS NOT NULL;
ALTER TABLE "tracks" ADD "tracker_id" character varying;
CREATE INDEX "idx_tracks_user_tracker_end_at" ON "tracks" ("user_id", "tracker_id", "end_at");
ALTER TABLE "users" ADD "visits_redetected_at" timestamp(6);
CREATE INDEX "index_users_on_visits_redetected_at" ON "users" ("visits_redetected_at");
CREATE UNIQUE INDEX "index_tracks_on_user_tracker_start_end_unique" ON "tracks" (user_id, COALESCE(tracker_id, ''), start_at, end_at);
DROP INDEX index_tracks_on_user_start_end_unique;
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('places@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, created_at, updated_at) VALUES ('Ownerless cafe', 12.373, 51.340, '2026-01-02 00:00:00', '2026-01-02 00:00:00');
INSERT INTO places (name, longitude, latitude, user_id, created_at, updated_at)
  SELECT 'Owned bakery', 12.374, 51.341, id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'places@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'places@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, tracker_id, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), 'phone', '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'places@example.test';
