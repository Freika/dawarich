defmodule Dawarich.Repo.Migrations.CreateStatsWorkState do
  use Ecto.Migration

  def up do
    "../sql/20261003120000_stats_work_state.sql"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.stats_geocoded_days, phoenix.cursors")
end
