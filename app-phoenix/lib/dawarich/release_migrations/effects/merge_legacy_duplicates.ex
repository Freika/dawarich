defmodule Dawarich.ReleaseMigrations.Effects.MergeLegacyDuplicates do
  @moduledoc false
  @sql """
      WITH candidates AS (
        SELECT id, user_id, timestamp,
               ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography AS target_lonlat
        FROM points
        WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL
      ), keepers AS (
        SELECT DISTINCT ON (c.user_id, c.timestamp, c.target_lonlat)
               c.user_id, c.timestamp, c.target_lonlat, COALESCE(existing.id, c.id) AS keeper_id
        FROM candidates c
        LEFT JOIN points existing
          ON existing.user_id = c.user_id AND existing.timestamp = c.timestamp
          AND existing.lonlat = c.target_lonlat
        ORDER BY c.user_id, c.timestamp, c.target_lonlat, c.id
      ), duplicates AS (
        SELECT c.id, k.keeper_id
        FROM candidates c
        JOIN keepers k
          ON k.user_id = c.user_id AND k.timestamp = c.timestamp AND k.target_lonlat = c.target_lonlat
        WHERE c.id <> k.keeper_id
      ), merged_data AS (
        SELECT d.keeper_id,
               (ARRAY_AGG(p.raw_data ORDER BY p.id)
                 FILTER (WHERE p.raw_data IS NOT NULL AND p.raw_data <> '{}'::jsonb))[1] AS raw_data,
               MIN(p.visit_id) AS visit_id, MIN(p.track_id) AS track_id
        FROM duplicates d
        JOIN points p ON p.id = d.id
        GROUP BY d.keeper_id
      ), updated_keepers AS (
        UPDATE points keeper
        SET raw_data = COALESCE(NULLIF(keeper.raw_data, '{}'::jsonb), m.raw_data, keeper.raw_data),
            visit_id = COALESCE(keeper.visit_id, m.visit_id),
            track_id = COALESCE(keeper.track_id, m.track_id)
        FROM merged_data m
        WHERE keeper.id = m.keeper_id
      ), deleted AS (
        DELETE FROM points USING duplicates
        WHERE points.id = duplicates.id
        RETURNING points.user_id, points.import_id
      ), deleted_user_counts AS (
        SELECT user_id, COUNT(*) AS count FROM deleted GROUP BY user_id
      ), updated_users AS (
        UPDATE users SET points_count = GREATEST(users.points_count - d.count, 0)
        FROM deleted_user_counts d WHERE users.id = d.user_id
      ), deleted_import_counts AS (
        SELECT import_id, COUNT(*) AS count FROM deleted WHERE import_id IS NOT NULL GROUP BY import_id
      ), updated_imports AS (
        UPDATE imports SET points_count = GREATEST(imports.points_count - d.count, 0)
        FROM deleted_import_counts d WHERE imports.id = d.import_id
      )
      SELECT COUNT(*) FROM deleted
  """
  def run(repo) do
    [[count]] = repo.query!(@sql, [], log: false, timeout: :infinity).rows
    count
  end
end
