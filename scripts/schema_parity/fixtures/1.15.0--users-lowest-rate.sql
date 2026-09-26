INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rate-one@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rate-two@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rate-three@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('rate-four@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at, deleted_at) VALUES ('rate-gone@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{"rps": 5}', '{"p":"m9JxX7FGbeWPbIWiKEQF87yMr26xGbUjdN9SdJLIpRh6fG6tocBa9I4=","h":{"iv":"fBYqkmdEcRGCOd0n","at":"REYewMt067RANXlsIB0J3g=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rate-one@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{"rps": "2"}', '{"p":"m9JxX7FGbeWPbIWiKEQF87yMr26xGbUjdN9SdJLIpRh6fG6tocBa9I4=","h":{"iv":"fBYqkmdEcRGCOd0n","at":"REYewMt067RANXlsIB0J3g=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rate-two@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{"rps": 2}', '{"p":"m9JxX7FGbeWPbIWiKEQF87yMr26xGbUjdN9SdJLIpRh6fG6tocBa9I4=","h":{"iv":"fBYqkmdEcRGCOd0n","at":"REYewMt067RANXlsIB0J3g=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rate-three@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{}', '{"p":"m9JxX7FGbeWPbIWiKEQF87yMr26xGbUjdN9SdJLIpRh6fG6tocBa9I4=","h":{"iv":"fBYqkmdEcRGCOd0n","at":"REYewMt067RANXlsIB0J3g=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'rate-four@example.test';
