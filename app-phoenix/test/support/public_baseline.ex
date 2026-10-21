defmodule Dawarich.PublicBaseline do
  @moduledoc false

  def ensure_current!(repo) do
    sql = Dawarich.ReleaseMigrator.baseline_sql()

    unless current?(repo, versions(sql)) do
      Dawarich.ScratchCase.recreate_public!(repo)
      repo.query!(sql, [], query_type: :text, log: false)
    end

    :ok
  end

  defp current?(repo, expected) do
    present =
      repo.query!(
        "SELECT to_regclass('public.schema_migrations') IS NOT NULL " <>
          "AND to_regclass('public.job_outbox') IS NOT NULL",
        [],
        log: false
      ).rows

    present == [[true]] &&
      repo.query!("SELECT version FROM public.schema_migrations ORDER BY version", [], log: false).rows ==
        expected
  end

  defp versions(sql) do
    Regex.scan(~r/INSERT INTO "schema_migrations" \(version\) VALUES\s+([^;]+);/, sql)
    |> Enum.flat_map(fn [_, values] -> Regex.scan(~r/\((\d+)\)/, values) end)
    |> Enum.map(fn [_, version] -> [version] end)
    |> Enum.sort()
  end
end
