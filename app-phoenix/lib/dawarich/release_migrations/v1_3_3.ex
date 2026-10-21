defmodule Dawarich.ReleaseMigrations.V1_3_3 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.3.3"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260310000001", &drop_redundant_indexes/1, transaction: false},
      {"20260310000002", &add_composite_indexes_and_drop_low_selectivity/1, transaction: false},
      {"20260310000003", &add_unique_index_to_place_visits/1, transaction: false},
      {"20260310000006", &fix_tracks_original_path_srid/1}
    ]
  end

  defp drop_redundant_indexes(repo) do
    opts = [algorithm: :concurrently, if_exists: true]
    remove_index_by_columns(repo, "points", ["user_id"], opts)
    remove_index_by_columns(repo, "points", ["timestamp"], opts)
    remove_index_by_columns(repo, "track_segments", ["track_id"], opts)
    remove_index_by_columns(repo, "track_segments", ["transportation_mode"], opts)
  end

  defp add_composite_indexes_and_drop_low_selectivity(repo) do
    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_points_track_id_timestamp" ON "points" ("track_id", "timestamp");|
    )

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_tracks_user_id_start_at" ON "tracks" ("user_id", "start_at");|
    )

    if index?(repo, "points",
         name: "index_points_on_user_id_and_reverse_geocoded_at",
         columns: ["user_id", "reverse_geocoded_at"]
       ) do
      sql!(repo, ~S|DROP INDEX CONCURRENTLY "index_points_on_user_id_and_reverse_geocoded_at";|)
    end
  end

  defp add_unique_index_to_place_visits(repo) do
    if table?(repo, "place_visits") do
      sql!(
        repo,
        ~S|DELETE FROM place_visits WHERE id IN ( SELECT id FROM ( SELECT id, ROW_NUMBER() OVER ( PARTITION BY visit_id, place_id ORDER BY id ) AS rn FROM place_visits ) duplicates WHERE rn > 1 );|
      )

      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "idx_place_visits_visit_id_place_id" ON "place_visits" ("visit_id", "place_id");|
      )

      if index?(repo, "place_visits",
           name: "index_place_visits_on_visit_id",
           columns: ["visit_id"]
         ) do
        sql!(repo, ~S|DROP INDEX CONCURRENTLY "index_place_visits_on_visit_id";|)
      end
    end
  end

  defp fix_tracks_original_path_srid(repo) do
    sql!(repo, ~S"""
    SELECT UpdateGeometrySRID('tracks', 'original_path', 4326);
    SELECT UpdateGeometrySRID('trips', 'path', 4326);
    """)
  end
end
