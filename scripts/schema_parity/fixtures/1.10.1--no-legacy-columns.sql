ALTER TABLE points DROP COLUMN latitude, DROP COLUMN longitude;
CREATE INDEX "idx_points_user_id_legacy_tracker" ON "points" ("user_id") WHERE tracker_id IN ('google-maps-timeline-export', 'google-maps-phone-timeline-export');
INSERT INTO users (email, created_at, updated_at) VALUES ('current@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points (user_id, tracker_id, lonlat, "timestamp", created_at, updated_at)
  SELECT id, 'google-maps-timeline-export', NULL, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'current@example.test';
