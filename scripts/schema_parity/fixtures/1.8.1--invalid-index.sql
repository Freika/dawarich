CREATE UNIQUE INDEX index_digests_on_user_year_period_type_monthless ON digests (user_id, year, period_type) WHERE month IS NULL;
UPDATE pg_index SET indisvalid = false, indisready = false WHERE indexrelid = 'index_digests_on_user_year_period_type_monthless'::regclass;
INSERT INTO users (email, created_at, updated_at) VALUES ('yearly@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00'), ('other@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 100, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 200, '2026-01-03 00:00:00', '2026-01-03 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2024, NULL, 0, 500, '2026-01-06 00:00:00', '2026-01-06 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 700, '2026-01-08 00:00:00', '2026-01-08 00:00:00' FROM users WHERE email = 'other@example.test';
