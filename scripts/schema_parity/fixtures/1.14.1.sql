ALTER TABLE "stats" ADD "flight_distance" bigint DEFAULT 0 NOT NULL;
ALTER TABLE "digests" ADD "flight_distance" bigint DEFAULT 0 NOT NULL;
ALTER TABLE "points" ADD CONSTRAINT "fk_points_track_id" FOREIGN KEY ("track_id") REFERENCES "tracks" ("id") NOT VALID;
ALTER TABLE "trips" ALTER COLUMN "distance" TYPE bigint;
CREATE VIEW trip_distances AS SELECT id, distance FROM trips;
INSERT INTO users (email, created_at, updated_at, visits_redetected_at) VALUES ('tracks@example.test', '2026-01-01 00:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
INSERT INTO tracks (start_at, end_at, user_id, original_path, created_at, updated_at)
  SELECT '2026-01-02 00:00:00', '2026-01-02 01:00:00', id, ST_GeomFromText('LINESTRING(12.37 51.34, 12.38 51.35)', 4326), '2026-01-02 00:00:00', '2026-01-02 00:00:00'
  FROM users WHERE email = 'tracks@example.test';
INSERT INTO points (user_id, track_id, "timestamp", created_at, updated_at)
  SELECT user_id, id, 1767315600, '2026-01-02 00:00:00', '2026-01-02 00:00:00' FROM tracks;
INSERT INTO points (user_id, "timestamp", created_at, updated_at)
  SELECT id, 1767319200, '2026-01-02 01:00:00', '2026-01-02 01:00:00' FROM users WHERE email = 'tracks@example.test';
ALTER TABLE points DISABLE TRIGGER ALL;
INSERT INTO points (user_id, track_id, "timestamp", created_at, updated_at)
  SELECT id, (SELECT max(id) + 1 FROM tracks), 1767322800, '2026-01-02 02:00:00', '2026-01-02 02:00:00' FROM users WHERE email = 'tracks@example.test';
INSERT INTO points (user_id, track_id, "timestamp", created_at, updated_at)
  SELECT id, (SELECT max(id) + 2 FROM tracks), 1767326400, '2026-01-02 03:00:00', '2026-01-02 03:00:00' FROM users WHERE email = 'tracks@example.test';
ALTER TABLE points ENABLE TRIGGER ALL;
