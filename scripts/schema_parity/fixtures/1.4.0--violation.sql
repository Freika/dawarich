INSERT INTO users (email, created_at, updated_at) VALUES ('dangling@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points (user_id, "timestamp", created_at, updated_at)
  SELECT id, 1767225600, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'dangling@example.test';
ALTER TABLE points DISABLE TRIGGER ALL;
INSERT INTO points (user_id, raw_data_archive_id, raw_data_archived, "timestamp", created_at, updated_at)
  SELECT id, (SELECT COALESCE(max(id), 0) + 1 FROM points_raw_data_archives), true, 1767229200, '2026-01-01 01:00:00', '2026-01-01 01:00:00' FROM users WHERE email = 'dangling@example.test';
ALTER TABLE points ENABLE TRIGGER ALL;
