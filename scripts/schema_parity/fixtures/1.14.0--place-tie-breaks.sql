INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('first@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('second@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('third@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO places (name, longitude, latitude, created_at, updated_at)
  SELECT name, 12.373, 51.340, '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM (VALUES ('Counted cafe'), ('Newest bar'), ('Smallest bakery'), ('Union deli'), ('Double diner'), ('Deleted visit kiosk')) AS p(name);
INSERT INTO places (name, longitude, latitude, user_id, created_at, updated_at)
  SELECT 'Owned library', 12.374, 51.341, id, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM users WHERE email = 'third@example.test';
INSERT INTO visits (user_id, place_id, started_at, ended_at, duration, name, deleted_at, created_at, updated_at)
  SELECT u.id, p.id, v.started_at::timestamp, v.started_at::timestamp + interval '1 hour', 60, v.label, v.deleted_at::timestamp, '2026-01-10 00:00:00', '2026-01-10 00:00:00'
  FROM (VALUES
    ('second@example.test', 'Counted cafe', '2026-01-02 10:00:00', 'counted-1', NULL),
    ('second@example.test', 'Counted cafe', '2026-01-03 10:00:00', 'counted-2', NULL),
    ('first@example.test', 'Counted cafe', '2026-01-09 10:00:00', 'counted-3', NULL),
    ('first@example.test', 'Newest bar', '2026-01-03 10:00:00', 'newest-1', NULL),
    ('second@example.test', 'Newest bar', '2026-01-05 10:00:00', 'newest-2', NULL),
    ('second@example.test', 'Smallest bakery', '2026-01-05 10:00:00', 'smallest-1', NULL),
    ('first@example.test', 'Smallest bakery', '2026-01-05 10:00:00', 'smallest-2', NULL),
    ('first@example.test', 'Union deli', '2026-01-06 10:00:00', 'union-1', NULL),
    ('first@example.test', 'Double diner', '2026-01-02 10:00:00', 'double-1', NULL),
    ('second@example.test', 'Double diner', '2026-01-03 10:00:00', 'double-2', NULL),
    ('third@example.test', 'Double diner', '2026-01-04 10:00:00', 'double-3', NULL),
    ('third@example.test', 'Deleted visit kiosk', '2026-01-02 10:00:00', 'deleted-1', '2026-01-08 00:00:00'),
    ('third@example.test', 'Deleted visit kiosk', '2026-01-03 10:00:00', 'deleted-2', '2026-01-08 00:00:00'),
    ('first@example.test', 'Deleted visit kiosk', '2026-01-04 10:00:00', 'deleted-3', NULL)
  ) AS v(email, place, started_at, label, deleted_at)
  JOIN users u ON u.email = v.email JOIN places p ON p.name = v.place;
INSERT INTO visits (user_id, started_at, ended_at, duration, name, created_at, updated_at)
  SELECT u.id, v.started_at::timestamp, v.started_at::timestamp + interval '1 hour', 60, v.label, '2026-01-10 00:00:00', '2026-01-10 00:00:00'
  FROM (VALUES ('second@example.test', '2026-01-02 10:00:00', 'union-2'), ('second@example.test', '2026-01-03 10:00:00', 'union-3')) AS v(email, started_at, label)
  JOIN users u ON u.email = v.email;
INSERT INTO place_visits (place_id, visit_id, created_at, updated_at)
  SELECT p.id, v.id, '2026-01-10 00:00:00', '2026-01-10 00:00:00'
  FROM (VALUES ('Union deli', 'union-2'), ('Union deli', 'union-3'), ('Double diner', 'double-1')) AS pv(place, label)
  JOIN places p ON p.name = pv.place JOIN visits v ON v.name = pv.label;
