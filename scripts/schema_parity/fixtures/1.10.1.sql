INSERT INTO users (email, created_at, updated_at) VALUES ('legacy@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points (user_id, latitude, longitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 51.340000, 12.370000, NULL, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'legacy@example.test';
INSERT INTO points (user_id, latitude, longitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 51.350000, 12.380000, ST_GeogFromText('SRID=4326;POINT(13.4 52.52)'), 1767319200, '2026-01-02 01:00:00', '2026-01-02 01:00:00' FROM users WHERE email = 'legacy@example.test';
INSERT INTO points (user_id, latitude, longitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, NULL, 12.390000, NULL, 1767322800, '2026-01-02 02:00:00', '2026-01-02 02:00:00' FROM users WHERE email = 'legacy@example.test';
INSERT INTO points (user_id, latitude, longitude, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 51.360000, NULL, NULL, 1767326400, '2026-01-02 03:00:00', '2026-01-02 03:00:00' FROM users WHERE email = 'legacy@example.test';
