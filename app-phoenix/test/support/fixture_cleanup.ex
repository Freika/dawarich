defmodule Dawarich.FixtureCleanup do
  @moduledoc false

  def delete!(repo, tables) do
    %{rows: ordered} =
      repo.query!(
        """
        WITH RECURSIVE dependents(oid, path) AS (
          SELECT name::regclass::oid, ARRAY[name::regclass::oid]
          FROM unnest($1::text[]) AS name
          UNION ALL
          SELECT fk.conrelid, d.path || fk.conrelid
          FROM dependents d JOIN pg_constraint fk ON fk.confrelid = d.oid
          WHERE fk.contype = 'f' AND NOT fk.conrelid = ANY(d.path)
        )
        SELECT oid::regclass::text FROM dependents
        GROUP BY oid ORDER BY max(cardinality(path)) DESC, oid
        """,
        [tables],
        log: false
      )

    sql = Enum.map_join(ordered, "; ", fn [table] -> "DELETE FROM #{table}" end)
    repo.query!(sql, [], query_type: :text, log: false)
    :ok
  end
end
