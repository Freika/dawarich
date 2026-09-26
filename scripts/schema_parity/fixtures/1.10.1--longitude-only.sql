ALTER TABLE points DROP COLUMN latitude;
INSERT INTO users (email, created_at, updated_at) VALUES ('longitude@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points (user_id, longitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 12.370000, NULL, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'longitude@example.test';
