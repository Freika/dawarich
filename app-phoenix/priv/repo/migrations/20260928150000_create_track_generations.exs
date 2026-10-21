defmodule Dawarich.Repo.Migrations.CreateTrackGenerations do
  use Ecto.Migration

  @sql Path.join(:code.priv_dir(:dawarich), "repo/sql/20260928150000_track_generations.sql")

  def up do
    @sql
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.track_generation_chunks, phoenix.track_generations")
end
