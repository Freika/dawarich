INSERT INTO schema_migrations (version) VALUES ('20260805120000');
ALTER TABLE "visits" ADD "deleted_at" timestamp(6);
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('tombstones@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL);
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at)
  SELECT id, '2026-01-02 10:00:00', '2026-01-02 11:00:00', 60, 'Declined cafe', 2, '2026-01-02 12:00:00', '2026-01-02 12:00:00' FROM users WHERE email = 'tombstones@example.test';
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at, deleted_at)
  SELECT id, '2026-01-03 10:00:00', '2026-01-03 11:00:00', 60, 'Tombstoned bakery', 2, '2026-01-03 12:00:00', '2026-01-03 12:00:00', '2026-01-04 00:00:00' FROM users WHERE email = 'tombstones@example.test';
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at)
  SELECT id, '2026-01-04 10:00:00', '2026-01-04 11:00:00', 60, 'Confirmed park', 1, '2026-01-04 12:00:00', '2026-01-04 12:00:00' FROM users WHERE email = 'tombstones@example.test';
