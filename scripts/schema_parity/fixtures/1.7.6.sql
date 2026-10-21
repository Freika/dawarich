CREATE UNIQUE INDEX "index_tracks_on_user_start_end_unique" ON "tracks" ("user_id", "start_at", "end_at");
INSERT INTO users (email, created_at, updated_at) VALUES ('first@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at) VALUES ('second@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email IN ('first@example.test', 'second@example.test');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 02:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.39 51.36)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'first@example.test';
