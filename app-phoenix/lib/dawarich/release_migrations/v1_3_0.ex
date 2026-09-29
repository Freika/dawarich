defmodule Dawarich.ReleaseMigrations.V1_3_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.3.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260216190000", &add_unique_index_to_raw_data_archives/1, transaction: false},
      {"20260217000000", &optimize_points_indexes/1, transaction: false},
      {"20260217000001", &backfill_motion_data_from_raw_data/1},
      {"20260222215414", &add_error_message_to_imports/1}
    ]
  end

  defp add_unique_index_to_raw_data_archives(repo) do
    sql!(
      repo,
      ~S|CREATE UNIQUE INDEX CONCURRENTLY "index_raw_data_archives_uniqueness" ON "points_raw_data_archives" ("user_id", "year", "month", "chunk_number");|
    )
  end

  defp optimize_points_indexes(repo) do
    unless column?(repo, "points", "motion_data") do
      sql!(repo, ~S|ALTER TABLE "points" ADD "motion_data" jsonb DEFAULT '{}' NOT NULL;|)
    end

    if index?(repo, "points", name: "idx_points_user_city") do
      sql!(repo, ~S|DROP INDEX  "idx_points_user_city";|)
    end

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_not_reverse_geocoded" ON "points" ("id") WHERE reverse_geocoded_at IS NULL;|
    )

    if index?(repo, "points", name: "index_points_on_reverse_geocoded_at") do
      sql!(repo, ~S|DROP INDEX  "index_points_on_reverse_geocoded_at";|)
    end
  end

  defp backfill_motion_data_from_raw_data(_repo),
    do: {:jobs, [job("DataMigrations::BackfillMotionDataJob")]}

  defp add_error_message_to_imports(repo) do
    sql!(repo, ~S|ALTER TABLE "imports" ADD "error_message" text;|)
  end
end
