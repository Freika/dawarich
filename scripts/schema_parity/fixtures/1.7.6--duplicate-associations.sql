INSERT INTO users (email, created_at, updated_at) VALUES ('associations@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), 101, '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'associations@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.39 51.36)', 4326), 102, '2026-01-02 00:05:00', '2026-01-02 00:05:00'
  FROM users WHERE email = 'associations@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 02:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.40 51.37)', 4326), 103, '2026-01-02 00:10:00', '2026-01-02 00:10:00'
  FROM users WHERE email = 'associations@example.test';
INSERT INTO track_segments (track_id, start_index, end_index, distance, created_at, updated_at)
  SELECT t.id, s.start_index, s.end_index, t.distance * 10 + s.start_index, '2026-01-02 03:00:00', '2026-01-02 03:00:00'
  FROM tracks t JOIN (VALUES (101, 0, 1), (101, 1, 2), (102, 0, 2), (103, 0, 3)) AS s(track, start_index, end_index) ON s.track = t.distance;
INSERT INTO points (user_id, track_id, "timestamp", lonlat, created_at, updated_at)
  SELECT t.user_id, t.id, p.ts, ST_GeogFromText('POINT(12.37 51.34)'), '2026-01-02 03:00:00', '2026-01-02 03:00:00'
  FROM tracks t JOIN (VALUES (101, 1767312000), (101, 1767312060), (102, 1767312120), (103, 1767312180)) AS p(track, ts) ON p.track = t.distance;
INSERT INTO points (user_id, "timestamp", lonlat, created_at, updated_at)
  SELECT id, 1767312240, ST_GeogFromText('POINT(12.38 51.35)'), '2026-01-02 03:00:00', '2026-01-02 03:00:00'
  FROM users WHERE email = 'associations@example.test';
