defmodule Dawarich.MapTiles do
  @moduledoc false

  def sql(:points) do
    """
    WITH bounds AS (SELECT ST_TileEnvelope($5::int, $6::int, $7::int) AS tile,
      ST_TileEnvelope($5::int, $6::int, $7::int, margin => 0.0625) AS expanded),
    candidates AS (
      SELECT p.*, ST_Transform(p.lonlat::geometry,3857) AS projected
      FROM points p, bounds b WHERE p.user_id = $1 AND p.timestamp BETWEEN $2 AND $3
        AND (p.anomaly = false OR p.anomaly IS NULL)
        AND ($4::bigint IS NULL OR p.import_id = $4)
        AND ST_Intersects(p.lonlat::geometry,ST_Transform(b.expanded,4326))
    ), features AS (
      SELECT count(*) AS count, min(timestamp) AS timestamp, max(timestamp) AS max_timestamp,
        CASE WHEN $5 >= 5 THEN min(id) END AS id,
        CASE WHEN $5 >= 5 THEN min(battery) END AS battery,
        CASE WHEN $5 >= 5 THEN min(track_id) END AS track_id,
        CASE WHEN $5 >= 5 THEN min(lock_version) END AS revision,
        CASE WHEN $5 >= 5 THEN min(altitude) END AS altitude,
        CASE WHEN $5 >= 5 THEN min(velocity) END AS velocity,
        CASE WHEN $5 >= 5 THEN min(ST_Y(lonlat::geometry)) END AS latitude,
        CASE WHEN $5 >= 5 THEN min(ST_X(lonlat::geometry)) END AS longitude,
        ST_AsMVTGeom(ST_Centroid(ST_Collect(projected)), b.tile,4096,256,true) AS geom
      FROM candidates, bounds b
      GROUP BY b.tile, ST_SnapToGrid(projected,40075016.685578488 / power(2,$5) / 512 * CASE WHEN $5 < 14 THEN 4 ELSE 1 END)
    ) SELECT ST_AsMVT(features.*, 'points',4096,'geom') FROM features WHERE geom IS NOT NULL
    """
  end

  def sql(:tracks) do
    """
    WITH bounds AS (SELECT ST_TileEnvelope($5::int,$6::int,$7::int) AS tile,
      ST_TileEnvelope($5::int,$6::int,$7::int,margin => 0.0625) AS expanded),
    candidates AS (
      SELECT t.*,
        CASE WHEN ($4::bigint IS NOT NULL OR extract(epoch FROM t.start_at) < $2 OR extract(epoch FROM t.end_at) > $3)
          AND EXISTS(SELECT 1 FROM points p WHERE p.track_id=t.id AND p.user_id=$1)
        THEN (SELECT ST_MakeLine(p.lonlat::geometry ORDER BY p.timestamp,p.id) FROM points p
          WHERE p.track_id=t.id AND p.user_id=$1 AND p.timestamp BETWEEN $2 AND $3
            AND (p.anomaly=false OR p.anomaly IS NULL) AND ($4::bigint IS NULL OR p.import_id=$4))
        ELSE t.original_path END AS path
      FROM tracks t WHERE t.user_id=$1 AND extract(epoch FROM t.end_at) >= $2
        AND extract(epoch FROM t.start_at) <= $3
        AND ($4::bigint IS NULL OR EXISTS(SELECT 1 FROM points p WHERE p.track_id=t.id AND p.user_id=$1 AND p.import_id=$4))
    ), features AS (
      SELECT id, '#3b82f6'::text AS color,
        to_char(start_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS start_at,
        to_char(end_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS end_at,
        extract(epoch FROM start_at)::bigint AS start_timestamp, extract(epoch FROM end_at)::bigint AS end_timestamp,
        lock_version AS revision, distance, avg_speed, duration,
        ST_AsMVTGeom(CASE WHEN $5 < 14 THEN ST_Simplify(ST_Transform(path,3857),40075016.685578488/power(2,$5)/512)
          ELSE ST_Transform(path,3857) END,b.tile,4096,256,true) AS geom
      FROM candidates, bounds b WHERE ST_Intersects(path,ST_Transform(b.expanded,4326))
    ) SELECT ST_AsMVT(features.*,'tracks',4096,'geom') FROM features WHERE geom IS NOT NULL
    """
  end
end
