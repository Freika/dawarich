INSERT INTO users (email, created_at, updated_at) VALUES ('yearly@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00'), ('other@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 100, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 200, '2026-01-03 00:00:00', '2026-01-03 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 300, '2026-01-04 00:00:00', '2026-01-04 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 1, 400, '2026-01-05 00:00:00', '2026-01-05 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2024, NULL, 0, 500, '2026-01-06 00:00:00', '2026-01-06 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, 1, 0, 600, '2026-01-07 00:00:00', '2026-01-07 00:00:00' FROM users WHERE email = 'yearly@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 700, '2026-01-08 00:00:00', '2026-01-08 00:00:00' FROM users WHERE email = 'other@example.test';
INSERT INTO digests (user_id, year, month, period_type, distance, created_at, updated_at)
  SELECT id, 2025, NULL, 0, 800, '2026-01-09 00:00:00', '2026-01-09 00:00:00' FROM users WHERE email = 'other@example.test';
