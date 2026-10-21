INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('geocoder@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.example.test", "use_https": false}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'geocoder@example.test';
