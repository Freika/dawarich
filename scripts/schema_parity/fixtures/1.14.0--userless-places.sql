INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('visitor@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, created_at, updated_at) VALUES ('Ownerless cafe', 12.373, 51.340, '2026-01-02 00:00:00', '2026-01-02 00:00:00');
INSERT INTO visits (user_id, place_id, started_at, ended_at, duration, name, created_at, updated_at)
  SELECT u.id, p.id, '2026-01-03 10:00:00', '2026-01-03 11:00:00', 60, 'Ownerless cafe', '2026-01-03 11:00:00', '2026-01-03 11:00:00'
  FROM users u, places p WHERE u.email = 'visitor@example.test' AND p.name = 'Ownerless cafe';
