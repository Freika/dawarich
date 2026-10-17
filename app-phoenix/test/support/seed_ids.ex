defmodule Dawarich.Test.SeedIds do
  @moduledoc false

  @consume_limit 100_000
  @gap "SELECT $1::text::regclass AS seq, $2::bigint - COALESCE(pg_sequence_last_value($1::text::regclass), 0) AS gap"

  def insert_all!(repo, table, rows, opts \\ []) do
    result = repo.insert_all(table, rows, opts)
    advance!(repo, table, Enum.map(rows, &Map.get(&1, :id)))
    result
  end

  def advance!(repo, table, ids) do
    case Enum.filter(ids, &is_integer/1) do
      [] ->
        :ok

      ids ->
        %{rows: [[sequence]]} =
          repo.query!("SELECT pg_get_serial_sequence($1, 'id')", [table], log: false)

        if sequence, do: forward!(repo, sequence, Enum.max(ids))
        :ok
    end
  end

  defp forward!(repo, sequence, id) do
    repo.query!(
      """
      SELECT setval(s.seq, $2::bigint, true) FROM (#{@gap}) s WHERE s.gap > #{@consume_limit}
      UNION ALL
      SELECT max(nextval(s.seq)) FROM (#{@gap}) s, generate_series(1, s.gap)
      WHERE s.gap BETWEEN 1 AND #{@consume_limit}
      """,
      [sequence, id],
      log: false
    )
  end
end
