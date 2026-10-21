defmodule Dawarich.Repo.Migrations.CreateImportRuns do
  use Ecto.Migration

  def up do
    execute(File.read!(Path.expand("../sql/20261001120000_import_runs.sql", __DIR__)))
  end

  def down, do: execute("DROP TABLE phoenix.import_runs")
end
