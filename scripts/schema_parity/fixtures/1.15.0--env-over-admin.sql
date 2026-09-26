INSERT INTO users (email, created_at, updated_at, visits_redetected_at, admin) VALUES ('env-admin@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', true);
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('env-member@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.admin.test", "use_https": true, "rps": 2}', '{"p":"hrMICP7dFmIC2EzUBHxYDiD9BhJLY+AcuuxBwRkV0hwnuhkkAw==","h":{"iv":"68K5mlDixm5VDau0","at":"39BBHBqIyBcwCdUgwz/cYw=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'env-admin@example.test';
