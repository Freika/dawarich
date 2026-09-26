INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rounding-a@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rounding-b@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.example.test", "rps": 0.30000000000000004}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rounding-a@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.example.test", "rps": 0.30000000000000004}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rounding-b@example.test';
