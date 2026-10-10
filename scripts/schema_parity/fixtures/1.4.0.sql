ALTER TABLE points DROP CONSTRAINT fk_rails_98d7bdf4ad;
CREATE INDEX "index_points_on_user_id" ON "points" ("user_id");
CREATE INDEX "index_points_on_unarchived" ON "points" ("user_id", "id") WHERE raw_data_archived = false AND raw_data != '{}';
CREATE INDEX "index_points_on_archived_uncleared" ON "points" ("user_id", "id") WHERE raw_data_archived = true AND raw_data != '{}';
INSERT INTO users (email, created_at, updated_at) VALUES ('archive@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO points_raw_data_archives (user_id, year, month, point_count, point_ids_checksum, archived_at, created_at, updated_at)
  SELECT id, 2026, 1, 1, 'checksum-2026-01', '2026-02-01 00:00:00', '2026-02-01 00:00:00', '2026-02-01 00:00:00' FROM users WHERE email = 'archive@example.test';
INSERT INTO points (user_id, raw_data_archive_id, raw_data_archived, "timestamp", created_at, updated_at)
  SELECT user_id, id, true, 1767225600, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM points_raw_data_archives;
INSERT INTO points (user_id, "timestamp", created_at, updated_at)
  SELECT id, 1767229200, '2026-01-01 01:00:00', '2026-01-01 01:00:00' FROM users WHERE email = 'archive@example.test';
