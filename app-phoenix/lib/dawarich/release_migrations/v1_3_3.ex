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
    remove_index_on_column(repo, "points", "user_id")
    remove_index_on_column(repo, "points", "timestamp")
    remove_index_on_column(repo, "track_segments", "track_id")
    remove_index_on_column(repo, "track_segments", "transportation_mode")
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

  defp remove_index_on_column(repo, table, column) do
    case index_names(repo, table, [column]) do
      [] ->
        :ok

      [name] ->
        sql!(repo, ~s|DROP INDEX CONCURRENTLY "#{String.replace(name, ~s("), ~s(""))}";|)

      names ->
        raise ArgumentError,
              "Multiple indexes found on #{table} columns [:#{column}]. " <>
                "Specify an index name from #{Enum.join(names, ", ")}"
    end
  end
end
