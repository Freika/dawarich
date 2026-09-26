defmodule Dawarich.ReleaseMigrations.V1_4_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

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
      sql!(repo, ~s|ALTER TABLE "points" DROP CONSTRAINT #{quote_ident(name)};|)
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

    sql!(repo, ~s|ALTER TABLE "points" VALIDATE CONSTRAINT #{quote_ident(name)};|)
  end

  defp archive_foreign_key(repo),
    do: foreign_key_name(repo, "points", "points_raw_data_archives", "raw_data_archive_id")
end
