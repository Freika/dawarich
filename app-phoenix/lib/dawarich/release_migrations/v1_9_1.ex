defmodule Dawarich.ReleaseMigrations.V1_9_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @unique_index "index_notes_on_attachable_and_noted_date"

  @notes_columns [
    {"title", "character varying"},
    {"body", "text"},
    {"attachable_type", "character varying"},
    {"attachable_id", "bigint"},
    {"noted_at", "timestamp(6)"},
    {"lonlat", "geography(POINT,4326)"}
  ]

  @duplicate_attachable_dates """
  SELECT attachable_type, attachable_id, CAST(noted_at AS date) AS noted_date FROM notes WHERE attachable_id IS NOT NULL GROUP BY attachable_type, attachable_id, CAST(noted_at AS date) HAVING COUNT(*) > 1
  """

  @impl true
  def release, do: "1.9.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260622090000", &backfill_notes_columns/1, transaction: false}
    ]
  end

  defp backfill_notes_columns(repo) do
    if table?(repo, "notes") do
      for {column, type} <- @notes_columns, not column?(repo, "notes", column) do
        sql!(repo, ~s|ALTER TABLE "notes" ADD "#{column}" #{type};|)
      end

      sql!(repo, ~S"""
      CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_notes_on_attachable_type_and_attachable_id" ON "notes" ("attachable_type", "attachable_id");
      """)

      sql!(repo, ~S"""
      CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_notes_on_lonlat" ON "notes" USING gist ("lonlat");
      """)

      unless index_name?(repo, "notes", @unique_index), do: create_unique_index(repo)
    end
  end

  defp create_unique_index(repo) do
    ensure_no_duplicate_attachable_dates!(repo)

    sql!(repo, ~S"""
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_notes_on_attachable_and_noted_date ON notes (attachable_type, attachable_id, (CAST(noted_at AS date))) WHERE attachable_id IS NOT NULL;
    """)
  end

  defp ensure_no_duplicate_attachable_dates!(repo) do
    case repo.query!(@duplicate_attachable_dates, [], log: false).num_rows do
      0 ->
        :ok

      groups ->
        raise "Cannot create unique index #{@unique_index}: #{groups} duplicate " <>
                "(attachable_type, attachable_id, noted_at::date) group(s) exist in the notes table. " <>
                "Resolve the duplicates and re-run this migration."
    end
  end
end
