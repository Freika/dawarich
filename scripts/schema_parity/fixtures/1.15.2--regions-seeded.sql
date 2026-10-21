INSERT INTO countries (name, iso_a2, iso_a3, geom, created_at, updated_at) VALUES
  ('Germany', 'DE', 'DEU', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00');
