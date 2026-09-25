defmodule Dawarich.ReleaseMigrations.V1_4_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @archive_foreign_key """
  SELECT c.conname::text
  FROM pg_constraint c
  JOIN pg_class t1 ON c.conrelid = t1.oid
  JOIN pg_class t2 ON c.confrelid = t2.oid
  JOIN pg_namespace n ON c.connamespace = n.oid
  WHERE c.contype = 'f' AND t1.relname = 'points' AND n.nspname = ANY (current_schemas(false))
    AND t2.oid::regclass::text = 'points_raw_data_archives'
    AND ARRAY(
      SELECT a.attname::text
      FROM generate_subscripts(c.conkey, 1) AS idx
      JOIN pg_attribute a ON a.attrelid = t1.oid AND a.attnum = c.conkey[idx]
      ORDER BY idx
    ) = ARRAY['raw_data_archive_id']
  ORDER BY c.conname
  LIMIT 1
  """

  @impl true
  def release, do: "1.4.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260318000001", &change_archive_fk_to_restrict/1},
      {"20260320000001", &restore_points_user_id_index/1, transaction: false},
      {"20260320000002", &add_archival_partial_indexes_to_points/1, transaction: false},
      {"20260322000001", &validate_archive_fk_restrict/1}
    ]
  end

  defp change_archive_fk_to_restrict(repo) do
    if name = archive_foreign_key(repo) do
      sql!(repo, ~s|ALTER TABLE "points" DROP CONSTRAINT #{quote_name(name)};|)
    end

    sql!(repo, ~S"""
    ALTER TABLE "points" ADD CONSTRAINT "fk_rails_98d7bdf4ad"
    FOREIGN KEY ("raw_data_archive_id")
      REFERENCES "points_raw_data_archives" ("id")
     ON DELETE RESTRICT NOT VALID;
    """)
  end

  defp restore_points_user_id_index(repo) do
    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_user_id" ON "points" ("user_id");|
    )
  end

  defp add_archival_partial_indexes_to_points(repo) do
    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_unarchived" ON "points" ("user_id", "id") WHERE raw_data_archived = false AND raw_data != '{}';|
    )

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_archived_uncleared" ON "points" ("user_id", "id") WHERE raw_data_archived = true AND raw_data != '{}';|
    )
  end

  defp validate_archive_fk_restrict(repo) do
    name =
      archive_foreign_key(repo) ||
        raise ArgumentError, "Table 'points' has no foreign key for points_raw_data_archives"

    sql!(repo, ~s|ALTER TABLE "points" VALIDATE CONSTRAINT #{quote_name(name)};|)
  end

  defp archive_foreign_key(repo), do: select_value(repo, @archive_foreign_key)

  defp quote_name(name), do: ~s("#{String.replace(name, ~s("), ~s(""))}")
end
