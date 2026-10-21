defmodule Dawarich.Repo.Migrations.CreateCableEvents do
  use Ecto.Migration

  def up do
    "../sql/20261004130000_cable_events.sql"
    |> Path.expand(__DIR__)
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.cable_events, phoenix.cable_streams")
end
