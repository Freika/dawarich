INSERT INTO users (email, created_at, updated_at) VALUES ('first@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at) VALUES ('second@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email IN ('first@example.test', 'second@example.test');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 02:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.39 51.36)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'first@example.test';
INSERT INTO track_segments (track_id, start_index, end_index, created_at, updated_at)
  SELECT id, 0, 1, '2026-01-02 03:00:00', '2026-01-02 03:00:00' FROM tracks;
INSERT INTO points (user_id, track_id, "timestamp", lonlat, created_at, updated_at)
  SELECT user_id, id, extract(epoch FROM end_at)::integer, ST_GeogFromText('POINT(12.37 51.34)'), '2026-01-02 03:00:00', '2026-01-02 03:00:00' FROM tracks;
