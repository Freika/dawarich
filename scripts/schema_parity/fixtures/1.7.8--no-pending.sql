ALTER TABLE "tracks" ADD "tracker_id" character varying;
INSERT INTO users (email, created_at, updated_at) VALUES ('owner@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, user_id, created_at, updated_at)
  SELECT 'Owned bakery', 12.374, 51.341, id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'owner@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, tracker_id, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), 'phone', '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'owner@example.test';
