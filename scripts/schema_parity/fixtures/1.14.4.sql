INSERT INTO point_sources (digest, created_at, updated_at) VALUES ('0123456789abcdef0123456789abcdef', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
DROP INDEX index_stats_on_user_id_year_month;
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('stats@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO stats (year, month, distance, user_id, created_at, updated_at)
  SELECT 2026, 1, 100, id, '2026-02-01 00:00:00', '2026-02-01 00:00:00' FROM users WHERE email = 'stats@example.test';
INSERT INTO stats (year, month, distance, user_id, created_at, updated_at)
  SELECT 2026, 1, 200, id, '2026-02-02 00:00:00', '2026-02-02 00:00:00' FROM users WHERE email = 'stats@example.test';
INSERT INTO stats (year, month, distance, user_id, created_at, updated_at)
  SELECT 2026, 2, 300, id, '2026-03-01 00:00:00', '2026-03-01 00:00:00' FROM users WHERE email = 'stats@example.test';
