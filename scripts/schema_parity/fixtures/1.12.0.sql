ALTER TABLE "visits" ADD "detection_version" smallint;
INSERT INTO users (email, settings, created_at, updated_at, visits_redetected_at) VALUES
  ('thresholds@example.test', '{"transportation_thresholds": {"walking": 7}, "fog_of_war_meters": "50"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-05 00:00:00'),
  ('expert-thresholds@example.test', '{"transportation_expert_thresholds": {"cycling": 25}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('expert-mode@example.test', '{"transportation_expert_mode": true, "meters_between_routes": "500"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('gap@example.test', '{"stay_max_gap_minutes": 30, "minutes_between_routes": "30"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-06 00:00:00'),
  ('density@example.test', '{"visit_density_fill_enabled": true}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL),
  ('current@example.test', '{"fog_of_war_meters": "100"}', '2026-01-01 00:00:00', '2026-01-01 00:00:00', NULL);
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at)
  SELECT id, '2026-01-02 10:00:00', '2026-01-02 11:00:00', 60, 'Declined cafe', 2, '2026-01-02 12:00:00', '2026-01-02 12:00:00' FROM users WHERE email = 'current@example.test';
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at)
  SELECT id, '2026-01-04 10:00:00', '2026-01-04 11:00:00', 60, 'Confirmed park', 1, '2026-01-04 12:00:00', '2026-01-04 12:00:00' FROM users WHERE email = 'current@example.test';
INSERT INTO visits (user_id, started_at, ended_at, duration, name, status, created_at, updated_at)
  SELECT id, '2026-01-05 10:00:00', '2026-01-05 11:00:00', 60, 'Suggested museum', 0, '2026-01-05 12:00:00', '2026-01-05 12:00:00' FROM users WHERE email = 'current@example.test';
