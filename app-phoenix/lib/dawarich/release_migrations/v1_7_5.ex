defmodule Dawarich.ReleaseMigrations.V1_7_5 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.5"

  @impl true
  def data_versions, do: []

  @impl true
  def steps,
    do: [{"20260503111800", &add_corrected_at_to_track_segments/1, transaction: false}]

  defp add_corrected_at_to_track_segments(repo) do
    unless column?(repo, "track_segments", "corrected_at") do
      sql!(repo, ~S|ALTER TABLE "track_segments" ADD "corrected_at" timestamp(6);|)
    end

    unless index?(repo, "track_segments",
             name: "index_track_segments_on_corrected_at",
             columns: ["corrected_at"]
           ) do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "index_track_segments_on_corrected_at" ON "track_segments" ("corrected_at") WHERE corrected_at IS NOT NULL;|
      )
    end
  end
end
