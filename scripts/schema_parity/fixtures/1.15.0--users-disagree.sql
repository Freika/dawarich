INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('disagree-a@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('disagree-b@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, admin) VALUES ('disagree-admin-a@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', true);
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, admin) VALUES ('disagree-admin-b@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', true);
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.a.test"}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'disagree-a@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.b.test"}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'disagree-b@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.a.test"}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'disagree-admin-a@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'nominatim', '{"host": "nominatim.c.test"}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'disagree-admin-b@example.test';
