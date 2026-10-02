defmodule Dawarich.Repo.Migrations.CreateWave6Tables do
  use Ecto.Migration

  @sql Path.join(:code.priv_dir(:dawarich), "repo/sql/20260928170000_wave6.sql")

  def up do
    @sql
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.raw_data_archive_chunks, phoenix.release_operations")
end
