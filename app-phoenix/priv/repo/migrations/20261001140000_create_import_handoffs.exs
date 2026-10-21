defmodule Dawarich.Repo.Migrations.CreateImportHandoffs do
  use Ecto.Migration

  def up do
    Path.expand("../sql/20261001140000_import_handoffs.sql", __DIR__)
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.each(&execute/1)
  end

  def down, do: execute("DROP TABLE phoenix.import_handoffs")
end
