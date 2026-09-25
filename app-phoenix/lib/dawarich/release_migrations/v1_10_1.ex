defmodule Dawarich.ReleaseMigrations.V1_10_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @backfill_lonlat """
  UPDATE points SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326) WHERE id IN ( SELECT id FROM points WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL LIMIT 50000 )
  """

  @impl true
  def release, do: "1.10.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260714090000", &drop_legacy_lat_lon_from_points/1, transaction: false},
      {"20260719180000", &enqueue_null_island_cleanup/1},
      {"20260719185000", &add_legacy_tracker_points_index/1, transaction: false},
      {"20260719190000", &enqueue_legacy_tracker_id_backfill/1}
    ]
  end

  defp drop_legacy_lat_lon_from_points(repo) do
    if column?(repo, "points", "latitude") or column?(repo, "points", "longitude") do
      if column?(repo, "points", "latitude") and column?(repo, "points", "longitude"),
        do: repeat_until_zero(repo, @backfill_lonlat)

      drop_legacy_columns(repo)
    end
  end

  defp drop_legacy_columns(repo) do
    case with_lock_retry(
           repo,
           fn ->
             sql!(repo, ~S"""
             SET LOCAL statement_timeout = 0;
             ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude;
             """)
           end,
           lock_timeout: "1s",
           attempts: 3,
           backoff_seconds: 3,
           on: [:lock_not_available, :query_canceled]
         ) do
      :acquired -> :ok
      {:not_acquired, _} -> {:jobs, [job("DataMigrations::DropLegacyLatLonJob")]}
    end
  end

  defp enqueue_null_island_cleanup(_repo),
    do: {:jobs, [job("DataMigrations::CleanupNullIslandJob")]}

  defp add_legacy_tracker_points_index(repo) do
    sql!(repo, ~S"""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_points_user_id_legacy_tracker" ON "points" ("user_id") WHERE tracker_id IN ('google-maps-timeline-export', 'google-maps-phone-timeline-export');
    """)
  end

  defp enqueue_legacy_tracker_id_backfill(_repo),
    do: {:jobs, [job("DataMigrations::RecalculatePerTrackerTracksJob")]}
end
