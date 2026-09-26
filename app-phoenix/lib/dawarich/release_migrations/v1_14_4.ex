defmodule Dawarich.ReleaseMigrations.V1_14_4 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @stats_index_valid """
  SELECT i.indisvalid
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  WHERE i.indrelid = 'stats'::regclass AND c.relname = 'index_stats_on_user_id_year_month'
  """

  @delete_duplicate_stats """
  DELETE FROM stats
  WHERE id IN (
    SELECT s1.id FROM stats s1
    WHERE EXISTS (
      SELECT 1 FROM stats s2
      WHERE s2.user_id = s1.user_id
        AND s2.year = s1.year
        AND s2.month = s1.month
        AND s2.id > s1.id
    )
    LIMIT 1000
  )
  """

  @impl true
  def release, do: "1.14.4"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260901070000", &enqueue_country_code_collision_repair/1},
      {"20260906103000", &repair_invalid_stats_unique_index/1, transaction: false}
    ]
  end

  defp enqueue_country_code_collision_repair(repo) do
    if backfill_allowed?() and exists?(repo, "SELECT 1 FROM point_sources") do
      {:jobs,
       [
         job("DataMigrations::BackfillPointCountryIdJob", [
           nil,
           50_000,
           %{"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]}
         ])
       ]}
    end
  end

  defp repair_invalid_stats_unique_index(repo) do
    valid = select_value(repo, @stats_index_valid)

    unless valid do
      repeat_until_zero(repo, @delete_duplicate_stats)

      if valid == false do
        sql!(repo, ~S"""
        DROP INDEX CONCURRENTLY "index_stats_on_user_id_year_month";
        """)
      end

      sql!(repo, ~S"""
      CREATE UNIQUE INDEX CONCURRENTLY "index_stats_on_user_id_year_month" ON "stats" ("user_id", "year", "month");
      """)
    end
  end
end
