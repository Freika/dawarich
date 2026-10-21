defmodule Dawarich.Repo.Migrations.CreateJobControlTables do
  use Ecto.Migration

  @sql Path.join(:code.priv_dir(:dawarich), "repo/sql/20260927120100_job_control.sql")

  def up do
    @sql
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down do
    execute("""
    DROP TABLE phoenix.trip_events, phoenix.app_version, phoenix.runtime_nodes,
      phoenix.processed_commands, phoenix.job_outbox_replays, phoenix.job_owners
    """)
  end
end
