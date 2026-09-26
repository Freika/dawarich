INSERT INTO users (email, created_at, updated_at) VALUES ('three@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at) VALUES ('pair@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-03 00:00:00', '2026-01-03 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), 201, '2026-01-03 00:00:00', '2026-01-03 00:00:00'
  FROM users WHERE email = 'three@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-03 00:00:00', '2026-01-03 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), 301, '2026-01-03 00:00:00', '2026-01-03 00:00:00'
  FROM users WHERE email = 'pair@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-03 00:00:00', '2026-01-03 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.39 51.36)', 4326), 202, '2026-01-03 00:05:00', '2026-01-03 00:05:00'
  FROM users WHERE email = 'three@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-03 00:00:00', '2026-01-03 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.39 51.36)', 4326), 302, '2026-01-03 00:05:00', '2026-01-03 00:05:00'
  FROM users WHERE email = 'pair@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-03 00:00:00', '2026-01-03 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.40 51.37)', 4326), 203, '2026-01-03 00:10:00', '2026-01-03 00:10:00'
  FROM users WHERE email = 'three@example.test';
INSERT INTO track_segments (track_id, start_index, end_index, distance, created_at, updated_at)
  SELECT id, 0, 1, distance, '2026-01-03 03:00:00', '2026-01-03 03:00:00' FROM tracks;
INSERT INTO points (user_id, track_id, "timestamp", lonlat, created_at, updated_at)
  SELECT user_id, id, 1767398400 + distance, ST_GeogFromText('POINT(12.37 51.34)'), '2026-01-03 03:00:00', '2026-01-03 03:00:00' FROM tracks;
