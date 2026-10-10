defmodule Dawarich.Test.SeedIds do
  @moduledoc false

  @consume_limit 100_000

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
    %{rows: [[gap]]} =
      repo.query!(
        "SELECT $2::bigint - COALESCE(pg_sequence_last_value($1::text::regclass), 0)",
        [sequence, id],
        log: false
      )

    cond do
      gap <= 0 ->
        :ok

      gap <= @consume_limit ->
        repo.query!(
          "SELECT max(nextval($1::text::regclass)) FROM generate_series(1, $2::bigint)",
          [sequence, gap],
          log: false
        )

      true ->
        repo.query!("SELECT setval($1::text::regclass, $2::bigint, true)", [sequence, id],
          log: false
        )
    end
  end
end
