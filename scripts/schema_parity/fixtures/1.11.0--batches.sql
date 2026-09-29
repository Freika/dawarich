INSERT INTO users (email, created_at, updated_at) VALUES ('batches@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO imports (name, user_id, source, created_at, updated_at) SELECT 'no-source-' || n || '.json', u.id, NULL, '2026-01-03 00:00:00', '2026-01-03 00:00:00' FROM users u CROSS JOIN generate_series(1, 5001) AS n WHERE u.email = 'batches@example.test' ORDER BY n;
INSERT INTO imports (name, user_id, source, created_at, updated_at) SELECT 'semantic.json', id, 0, '2026-01-03 00:00:00', '2026-01-03 00:00:00' FROM users WHERE email = 'batches@example.test';
