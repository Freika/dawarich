ALTER TABLE "users" ADD "deleted_at" timestamp(6);
CREATE INDEX "index_users_on_deleted_at" ON "users" ("deleted_at");
ALTER INDEX "index_digests_on_user_id_and_year_and_period_type" RENAME TO "index_digests_legacy_user_year_period";
INSERT INTO users (email, created_at, updated_at) VALUES ('first@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, deleted_at) VALUES ('deleted@example.test', '2026-01-02 00:00:00', '2026-01-02 00:00:00', '2026-01-05 00:00:00');
INSERT INTO users (email, created_at, updated_at) VALUES ('third@example.test', '2026-01-03 00:00:00', '2026-01-03 00:00:00');
UPDATE users SET api_key = 'first-key', updated_at = '2026-01-04 00:00:00' WHERE email = 'first@example.test';
INSERT INTO imports (name, user_id, source, created_at, updated_at)
  SELECT 'Semantic history', id, 0, '2026-01-06 00:00:00', '2026-01-06 00:00:00' FROM users WHERE email = 'third@example.test';
INSERT INTO imports (name, user_id, source, created_at, updated_at)
  SELECT 'OwnTracks', id, 1, '2026-01-06 00:00:00', '2026-01-06 00:00:00' FROM users WHERE email = 'first@example.test';
INSERT INTO imports (name, user_id, source, created_at, updated_at)
  SELECT 'GPX', id, 4, '2026-01-06 00:00:00', '2026-01-06 00:00:00' FROM users WHERE email = 'first@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-07 00:00:00', '2026-01-07 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)'), 1234.56, '2026-01-07 00:00:00', '2026-01-07 00:00:00'
  FROM users WHERE email = 'first@example.test';
INSERT INTO tracks (start_at, end_at, user_id, original_path, distance, created_at, updated_at)
  SELECT '2026-01-08 00:00:00', '2026-01-08 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)'), NULL, '2026-01-08 00:00:00', '2026-01-08 00:00:00'
  FROM users WHERE email = 'first@example.test';
