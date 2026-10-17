CREATE TABLE "regions" ("id" bigserial primary key, "code" character varying NOT NULL, "geom" geometry(MULTIPOLYGON,4326) NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
CREATE UNIQUE INDEX "index_regions_on_code" ON "regions" ("code");
CREATE INDEX "index_regions_on_geom" ON "regions" USING gist ("geom");
INSERT INTO regions (code, geom, created_at, updated_at) VALUES
  ('DE', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('DE-BE', ST_Multi(ST_GeomFromText('POLYGON((13 52, 14 52, 14 53, 13 53, 13 52))', 4326)), '2026-01-02 00:00:00', '2026-01-03 00:00:00'),
  ('FR', ST_Multi(ST_GeomFromText('POLYGON((-5 42, 8 42, 8 51, -5 51, -5 42))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('ZZ-01', ST_Multi(ST_GeomFromText('POLYGON((0 0, 2 2, 2 0, 0 2, 0 0))', 4326)), '2026-01-04 00:00:00', '2026-01-05 00:00:00');
INSERT INTO countries (name, iso_a2, iso_a3, geom, created_at, updated_at) VALUES
  ('Germany', 'DE', 'DEU', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
  ('France', 'FR', 'FRA', ST_Multi(ST_GeomFromText('POLYGON((-5 42, 8 42, 8 51, -5 51, -5 42))', 4326)), '2026-01-01 00:00:00', '2026-01-01 00:00:00');
