ALTER TABLE points DROP COLUMN longitude;
INSERT INTO users (email, created_at, updated_at) VALUES ('latitude@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points (user_id, latitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 51.340000, NULL, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'latitude@example.test';
