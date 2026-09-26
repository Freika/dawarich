INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('coerced@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at)
  SELECT id, 0, 'photon', '{"host": "photon.user.test", "use_https": true, "rps": 7}', '{"p":"ClcHqXCRawy9KJDT/ckGPQNTx6EdAEotSL2olgIjX7KOpqyAxw==","h":{"iv":"FsvY5Drim8MD9eWL","at":"0Ac6CBSb7rCXO1U1tFSyyg=="}}', true, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM users WHERE email = 'coerced@example.test';
