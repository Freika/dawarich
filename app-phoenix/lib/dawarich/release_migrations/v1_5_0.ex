defmodule Dawarich.ReleaseMigrations.V1_5_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.5.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260322000002", &drop_unused_points_indexes/1},
      {"20260323000001", &change_points_altitude_to_decimal/1},
      {"20260323000002", &backfill_altitude_from_raw_data/1},
      {"20260325183025", &add_anomaly_to_points/1, transaction: false},
      {"20260326192648", &add_demo_to_imports/1}
    ]
  end

  defp drop_unused_points_indexes(repo) do
    if index?(repo, "points", name: "index_points_on_country_id", columns: ["country_id"]) do
      sql!(repo, ~S|DROP INDEX  "index_points_on_country_id";|)
    end

    if index?(repo, "points", name: "index_points_on_archived_uncleared") do
      sql!(repo, ~S|DROP INDEX  "index_points_on_archived_uncleared";|)
    end

    if index?(repo, "points", name: "index_points_on_archived_true") do
      sql!(repo, ~S|DROP INDEX  "index_points_on_archived_true";|)
    end
  end

  defp change_points_altitude_to_decimal(repo) do
    unless column?(repo, "points", "altitude_decimal") do
      sql!(repo, ~S|ALTER TABLE "points" ADD "altitude_decimal" decimal(10,2);|)
    end
  end

  defp backfill_altitude_from_raw_data(_repo),
    do: {:jobs, [job("DataMigrations::BackfillAltitudeJob")]}

  defp add_anomaly_to_points(repo) do
    unless column?(repo, "points", "anomaly") do
      sql!(repo, ~S|ALTER TABLE "points" ADD "anomaly" boolean;|)
    end

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_not_anomaly" ON "points" ("anomaly") WHERE anomaly IS NOT TRUE;|
    )
  end

  defp add_demo_to_imports(repo) do
    unless column?(repo, "imports", "demo") do
      sql!(repo, ~S|ALTER TABLE "imports" ADD "demo" boolean DEFAULT FALSE NOT NULL;|)
    end
  end
end
