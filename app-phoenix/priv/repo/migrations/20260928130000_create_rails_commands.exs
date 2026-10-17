defmodule Dawarich.Repo.Migrations.CreateRailsCommands do
  use Ecto.Migration

  @sql Path.join(:code.priv_dir(:dawarich), "repo/sql/20260928130000_rails_commands.sql")

  def up do
    @sql
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.rails_commands, phoenix.rails_commands_dead")
end
