INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('malformed-key@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{}', '{"p":"","h":"headers"}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'malformed-key@example.test';
