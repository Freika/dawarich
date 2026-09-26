defmodule Dawarich.ReleaseMigrations.Unreleased do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @import_initial_delay_seconds 2 * 60
  @import_delay_seconds 10

  @impl true
  def release, do: "unreleased"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260923180000", &enqueue_ungated_achievements_backfill/1},
      {"20260925100000", &align_track_split_settings_defaults/1},
      {"20260925100100", &reenqueue_transportation_mode_backfills/1, transaction: false}
    ]
  end

  defp enqueue_ungated_achievements_backfill(_repo) do
    {:jobs, [job("DataMigrations::BackfillAchievementsJob")]}
  end

  defp align_track_split_settings_defaults(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ALTER COLUMN "settings" SET DEFAULT '{"fog_of_war_meters":"100","meters_between_routes":"500","minutes_between_routes":"30"}';
    """)
  end

  defp reenqueue_transportation_mode_backfills(repo) do
    tracks_job =
      if select_value(repo, "SELECT EXISTS (SELECT 1 FROM tracks)"),
        do: [job("DataMigrations::BackfillTransportationModesJob")],
        else: []

    import_jobs =
      repo.query!("SELECT id FROM imports WHERE source IN (0, 1, 2, 3, 6) ORDER BY id", [],
        log: false
      ).rows
      |> Enum.with_index(fn [import_id], index ->
        job(
          "TransportationModes::ImportBackfillJob",
          [import_id],
          @import_initial_delay_seconds + index * @import_delay_seconds
        )
      end)

    {:jobs, tracks_job ++ import_jobs}
  end
end
