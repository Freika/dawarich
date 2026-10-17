defmodule Dawarich.ReleaseMigrations.V1_7_7 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.7"

  @impl true
  def data_versions, do: []

  @impl true
  def steps, do: [{"20260504120000", &change_stats_distance_to_bigint/1}]

  defp change_stats_distance_to_bigint(repo) do
    sql!(
      repo,
      ~S|ALTER TABLE "stats" ALTER COLUMN "distance" TYPE bigint, ALTER COLUMN "distance" SET NOT NULL;|
    )
  end
end
