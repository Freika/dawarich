defmodule Dawarich.Repo.Migrations.CreateImportDestroyRuns do
  use Ecto.Migration

  def up,
    do: execute(File.read!(Path.expand("../sql/20261001170000_import_destroy_runs.sql", __DIR__)))

  def down, do: execute("DROP TABLE phoenix.import_destroy_runs")
end
