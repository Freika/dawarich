INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('member-a@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('member-b@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, admin) VALUES ('admin-a@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', true);
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, admin) VALUES ('admin-b@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', true);
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.a.test", "use_https": false}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'member-a@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'nominatim', '{"host": "nominatim.b.test", "use_https": true}', NULL, true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'member-b@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.admin.test", "use_https": true, "rps": 1.5}', '{"p":"hrMICP7dFmIC2EzUBHxYDiD9BhJLY+AcuuxBwRkV0hwnuhkkAw==","h":{"iv":"68K5mlDixm5VDau0","at":"39BBHBqIyBcwCdUgwz/cYw=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'admin-a@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.admin.test", "use_https": true, "rps": 0.5}', '{"p":"hrMICP7dFmIC2EzUBHxYDiD9BhJLY+AcuuxBwRkV0hwnuhkkAw==","h":{"iv":"68K5mlDixm5VDau0","at":"39BBHBqIyBcwCdUgwz/cYw=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'admin-b@example.test';
