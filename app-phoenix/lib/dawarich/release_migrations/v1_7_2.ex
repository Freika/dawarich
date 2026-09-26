defmodule Dawarich.ReleaseMigrations.V1_7_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps, do: [{"20260429180000", &drop_rails_pulse_tables/1}]

  defp drop_rails_pulse_tables(repo) do
    sql!(repo, ~S"""
    DROP TABLE IF EXISTS "rails_pulse_operations" CASCADE;
    DROP TABLE IF EXISTS "rails_pulse_summaries" CASCADE;
    DROP TABLE IF EXISTS "rails_pulse_requests" CASCADE;
    DROP TABLE IF EXISTS "rails_pulse_queries" CASCADE;
    DROP TABLE IF EXISTS "rails_pulse_routes" CASCADE;
    """)
  end
end
