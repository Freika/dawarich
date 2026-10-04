defmodule Dawarich.Repo.Migrations.CreateImportArchiveChildren do
  use Ecto.Migration

  def up,
    do:
      execute(
        File.read!(Path.expand("../sql/20261003070100_import_archive_children.sql", __DIR__))
      )

  def down, do: execute("DROP TABLE phoenix.import_archive_children")
end
