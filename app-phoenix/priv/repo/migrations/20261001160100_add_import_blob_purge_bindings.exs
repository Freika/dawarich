defmodule Dawarich.Repo.Migrations.AddImportBlobPurgeBindings do
  use Ecto.Migration

  def up do
    Path.expand("../sql/20261001160100_import_blob_purge_bindings.sql", __DIR__)
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.each(&execute/1)
  end

  def down do
    raise "Composite purge receipts are append-only; restoring a single-key receipt would lose authorization history"
  end
end
