defmodule Dawarich.Test.SeedIds do
  @moduledoc false

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

        if sequence do
          repo.query!(
            "SELECT setval($1::text::regclass, GREATEST($2::bigint, nextval($1::text::regclass)), true)",
            [sequence, Enum.max(ids)],
            log: false
          )
        end

        :ok
    end
  end
end
