defmodule Dawarich.ReleaseMigrations.V1_8_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @duplicate_yearly_digests """
  SELECT id FROM digests WHERE month IS NULL AND id NOT IN ( SELECT MIN(id) FROM digests WHERE month IS NULL GROUP BY user_id, year, period_type ) LIMIT 1000
  """

  @invalid_monthless_index """
  SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid WHERE c.relname = 'index_digests_on_user_year_period_type_monthless' AND i.indisvalid = false
  """

  @impl true
  def release, do: "1.8.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260610090000", &dedupe_yearly_digests_and_add_unique_index/1, transaction: false}
    ]
  end

  defp dedupe_yearly_digests_and_add_unique_index(repo) do
    delete_duplicate_yearly_digests(repo)

    if exists?(repo, @invalid_monthless_index) do
      sql!(repo, ~S"""
      DROP INDEX CONCURRENTLY IF EXISTS index_digests_on_user_year_period_type_monthless;
      """)
    end

    sql!(repo, ~S"""
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_digests_on_user_year_period_type_monthless
    ON digests (user_id, year, period_type)
    WHERE month IS NULL;
    """)
  end

  defp delete_duplicate_yearly_digests(repo) do
    case repo.query!(@duplicate_yearly_digests, [], log: false).rows do
      [] ->
        :ok

      rows ->
        repo.query!("DELETE FROM digests WHERE id = ANY($1)", [List.flatten(rows)], log: false)
        delete_duplicate_yearly_digests(repo)
    end
  end
end
