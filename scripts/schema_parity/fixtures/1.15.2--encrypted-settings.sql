INSERT INTO users (email, otp_secret, created_at, updated_at) VALUES ('encrypted@example.test', '{"p":"ZhQNn7aAvWsTyE8G3Jw+Ng==","h":{"iv":"3KGFcJUEz9JcQJ/I","at":"q+HNHW9PFScpNzekULIW3g==","i":"ODIxMA=="}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'locationiq', '{}', '{"p":"m9JxX7FGbeWPbIWiKEQF87yMr26xGbUjdN9SdJLIpRh6fG6tocBa9I4=","h":{"iv":"fBYqkmdEcRGCOd0n","at":"REYewMt067RANXlsIB0J3g=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'encrypted@example.test';
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'geoapify', '{}', '{"p":"DYfXwTnlxH6245HO3jYoabewt9Rh90stJNC0kJAwIn+x+40zWWHlZLkX9qUC02BEsoDIN0EoraO3dS5+DyPDIYOP","h":{"iv":"iCOFyIFX+DRxEYoS","at":"ADeXkTWwqR3f9wAk6FbhGg==","c":true}}', false, '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'encrypted@example.test';
INSERT INTO instance_settings (key, value, encrypted_value, created_at, updated_at) VALUES
  ('locationiq_api_key', NULL, '{"p":"H6bwLNoEmWVAwsvZLHBW5Lqpd8O/YacRn+19","h":{"iv":"E+Z3jRpmFsCpZSn6","at":"yjjsxWntSr/3aMl69pn6JA=="}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('photon_api_host', '"photon.example.test"', NULL, '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO trip_sources (user_id, provider, base_url, api_key, created_at, updated_at)
  SELECT id, 'trek', 'https://trek.example.test', '{"p":"wiyEhHzHyYR37Wt0NHXIgVI+KyE5hNicG5oIPQ==","h":{"iv":"WigA0N3nsgJOSzuS","at":"B7afhF1q1c99lwshv3SniQ=="}}', '2026-01-01 00:00:00', '2026-01-01 00:00:00'
  FROM users WHERE email = 'encrypted@example.test';
