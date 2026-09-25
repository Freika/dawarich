defmodule Dawarich.ReleaseMigrations.V1_7_6 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @duplicate_tracks "SELECT 1 FROM tracks GROUP BY user_id, start_at, end_at HAVING COUNT(*) > 1"

  @impl true
  def release, do: "1.7.6"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260508030000", &add_last_recalculated_at_to_trips/1},
      {"20260508193900", &dedupe_tracks_for_unique_index/1, transaction: false},
      {"20260508193923", &add_unique_index_to_tracks/1, transaction: false}
    ]
  end

  defp add_last_recalculated_at_to_trips(repo) do
    sql!(repo, ~S|ALTER TABLE "trips" ADD "last_recalculated_at" timestamp(6);|)
  end

  defp dedupe_tracks_for_unique_index(repo) do
    if exists?(repo, @duplicate_tracks),
      do: unported!("DataMigrations::DedupeTracksForUniqueIndexJob")
  end

  defp add_unique_index_to_tracks(repo) do
    unless index_name?(repo, "tracks", "index_tracks_on_user_start_end_unique") do
      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX CONCURRENTLY "index_tracks_on_user_start_end_unique" ON "tracks" ("user_id", "start_at", "end_at");|
      )
    end
  end
end
