INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('no-tracks@example.test', '2026-09-01 00:00:00', '2026-09-01 00:00:00', '2026-09-01 00:00:00');
INSERT INTO imports (name, user_id, source, created_at, updated_at) SELECT 'owntracks.rec', id, 1, '2026-09-03 00:00:00', '2026-09-03 00:00:00' FROM users WHERE email = 'no-tracks@example.test';
INSERT INTO imports (name, user_id, source, created_at, updated_at) SELECT 'ride.gpx', id, 4, '2026-09-03 00:00:00', '2026-09-03 00:00:00' FROM users WHERE email = 'no-tracks@example.test';
INSERT INTO imports (name, user_id, source, created_at, updated_at) SELECT 'semantic.json', id, 0, '2026-09-03 00:00:00', '2026-09-03 00:00:00' FROM users WHERE email = 'no-tracks@example.test';
