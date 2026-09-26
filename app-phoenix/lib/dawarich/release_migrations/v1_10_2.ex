defmodule Dawarich.ReleaseMigrations.V1_10_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.10.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260727120000", &add_name_locked_at_to_places/1},
      {"20260727130000", &enqueue_place_name_locks_backfill/1}
    ]
  end

  defp add_name_locked_at_to_places(repo) do
    unless column?(repo, "places", "name_locked_at") do
      sql!(repo, ~S"""
      ALTER TABLE "places" ADD "name_locked_at" timestamp(6);
      """)
    end
  end

  defp enqueue_place_name_locks_backfill(_repo),
    do: {:jobs, [job("DataMigrations::BackfillPlaceNameLocksJob")]}
end
