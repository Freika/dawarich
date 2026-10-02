defmodule Dawarich.Repo.Migrations.CreateImportBlobPurges do
  use Ecto.Migration

  def up do
    execute(File.read!(Path.expand("../sql/20261001160000_import_blob_purges.sql", __DIR__)))
  end

  def down, do: execute("DROP TABLE phoenix.import_blob_purges")
end
