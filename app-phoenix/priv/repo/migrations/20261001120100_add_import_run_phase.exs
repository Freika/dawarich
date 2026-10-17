defmodule Dawarich.Repo.Migrations.AddImportRunPhase do
  use Ecto.Migration

  def up do
    Path.expand("../sql/20261001120100_import_run_phase.sql", __DIR__)
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.each(&execute/1)
  end

  def down do
    execute("ALTER TABLE phoenix.import_runs DROP COLUMN attachment_snapshot, DROP COLUMN phase")
  end
end
