INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('visitor@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, created_at, updated_at) VALUES ('Visited cafe', 12.373, 51.340, '2026-01-02 00:00:00', '2026-01-02 00:00:00');
INSERT INTO places (name, longitude, latitude, created_at, updated_at) VALUES ('Unvisited cafe', 12.375, 51.342, '2026-01-02 00:00:00', '2026-01-02 00:00:00');
INSERT INTO places (name, longitude, latitude, user_id, created_at, updated_at)
  SELECT 'Owned unvisited bakery', 12.374, 51.341, id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'visitor@example.test';
INSERT INTO visits (user_id, place_id, started_at, ended_at, duration, name, created_at, updated_at)
  SELECT u.id, p.id, '2026-01-03 10:00:00', '2026-01-03 11:00:00', 60, 'Visited cafe', '2026-01-03 11:00:00', '2026-01-03 11:00:00'
  FROM users u, places p WHERE u.email = 'visitor@example.test' AND p.name = 'Visited cafe';
