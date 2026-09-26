defmodule Dawarich.ReleaseMigrations.V1_7_11 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.11"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260521223000", &drop_anomaly_and_track_generation_indexes/1, transaction: false},
      {"20260528102209", &add_demo(&1, "visits"), transaction: false},
      {"20260528102210", &add_demo(&1, "trips"), transaction: false},
      {"20260528102211", &add_demo(&1, "tags"), transaction: false},
      {"20260528102212", &add_demo(&1, "places"), transaction: false},
      {"20260529185458", &add_demo(&1, "tracks"), transaction: false}
    ]
  end

  defp drop_anomaly_and_track_generation_indexes(repo) do
    sql!(repo, "DROP INDEX CONCURRENTLY IF EXISTS index_points_on_not_anomaly;")
    sql!(repo, "DROP INDEX CONCURRENTLY IF EXISTS idx_points_track_generation;")
  end

  defp add_demo(repo, table) do
    unless column?(repo, table, "demo") do
      sql!(repo, ~s|ALTER TABLE "#{table}" ADD "demo" boolean DEFAULT FALSE NOT NULL;|)
    end

    sql!(
      repo,
      ~s|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_#{table}_on_demo_true" ON "#{table}" ("demo") WHERE demo = true;|
    )
  end
end
