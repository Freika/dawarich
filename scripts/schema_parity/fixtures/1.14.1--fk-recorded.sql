INSERT INTO schema_migrations (version) VALUES ('20260827200000');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('tracks@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'tracks@example.test';
INSERT INTO points (user_id, track_id, "timestamp", created_at, updated_at)
  SELECT user_id, id, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM tracks;
INSERT INTO points (user_id, track_id, "timestamp", created_at, updated_at)
  SELECT id, (SELECT max(id) + 1 FROM tracks), 1767322800, '2026-01-02 02:00:00', '2026-01-02 02:00:00' FROM users WHERE email = 'tracks@example.test';
