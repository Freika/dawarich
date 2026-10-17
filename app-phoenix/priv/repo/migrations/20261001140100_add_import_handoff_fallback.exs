defmodule Dawarich.Repo.Migrations.AddImportHandoffFallback do
  use Ecto.Migration

  def up do
    Path.expand("../sql/20261001140100_import_handoff_fallback.sql", __DIR__)
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.each(&execute/1)
  end

  def down, do: execute("ALTER TABLE phoenix.import_handoffs DROP COLUMN native_fallback")
end
