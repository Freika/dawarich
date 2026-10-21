defmodule Dawarich.Repo.Migrations.CreateWave2Tables do
  use Ecto.Migration

  @sql Path.join(:code.priv_dir(:dawarich), "repo/sql/20260928120000_wave2.sql")

  def up do
    @sql
    |> File.read!()
    |> String.split(";\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&execute/1)
  end

  def down do
    execute(
      "DROP TABLE phoenix.export_claims, phoenix.delivery_claims, phoenix.notification_events"
    )
  end
end
