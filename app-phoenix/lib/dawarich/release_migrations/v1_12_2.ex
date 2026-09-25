defmodule Dawarich.ReleaseMigrations.V1_12_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @redundant_points_indexes ~w[
    index_points_on_user_id
    index_points_on_track_id
    index_points_on_user_id_and_empty_geodata
  ]

  @impl true
  def release, do: "1.12.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260811120000", &enqueue_leaped_point_recalculation/1, transaction: false},
      {"20260813120000", &add_user_id_timestamp_lonlat_unique_index_to_points/1,
       transaction: false},
      {"20260813120100", &drop_redundant_points_indexes/1, transaction: false}
    ]
  end

  defp enqueue_leaped_point_recalculation(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = settings - ARRAY['anomaly_rules_recalculation_queued_at', 'anomaly_rules_recalculated_at', 'anomaly_rules_recalculation_failed_at']::text[] WHERE settings ?| ARRAY['anomaly_rules_recalculation_queued_at', 'anomaly_rules_recalculated_at', 'anomaly_rules_recalculation_failed_at']::text[];
    """)

    {:jobs, [job("DataMigrations::RecalculateAnomaliesJob")]}
  end

  defp add_user_id_timestamp_lonlat_unique_index_to_points(repo) do
    sql!(repo, ~S"""
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_user_id_timestamp_lonlat" ON "points" ("user_id", "timestamp", "lonlat");
    """)
  end

  defp drop_redundant_points_indexes(repo) do
    for name <- @redundant_points_indexes, index?(repo, "points", name: name) do
      sql!(repo, ~s|DROP INDEX CONCURRENTLY "#{name}";|)
    end
  end
end
