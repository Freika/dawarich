defmodule Dawarich.Visits.Calendar do
  @moduledoc false

  @series "FROM generate_series(date_trunc('month', to_timestamp($1::bigint)), " <>
            "to_timestamp($2::bigint) - interval '1 second', interval '1 month') AS m ORDER BY m"

  def next_day(_repo, _zone, ts, "fixed"), do: ts + 86_400

  def next_day(repo, zone, ts, "calendar"),
    do:
      repo
      |> in_zone(
        zone,
        "SELECT floor(extract(epoch FROM to_timestamp($1::bigint) + interval '1 day'))::bigint",
        [ts]
      )
      |> hd()
      |> hd()

  def year_ago(repo, zone),
    do:
      repo
      |> in_zone(
        zone,
        "SELECT floor(extract(epoch FROM now() - interval '12 months'))::bigint",
        []
      )
      |> hd()
      |> hd()

  def month_batches(repo, zone, start, stop),
    do:
      in_zone(
        repo,
        zone,
        "SELECT greatest(extract(epoch FROM m)::bigint, $1::bigint), " <>
          "least(extract(epoch FROM m + interval '1 month')::bigint - 1, $2::bigint) " <> @series,
        [start, stop]
      )

  def redetect_months(repo, zone, min, max),
    do:
      in_zone(
        repo,
        zone,
        "SELECT greatest(extract(epoch FROM m)::bigint, $1::bigint), " <>
          "least(extract(epoch FROM m + interval '1 month')::bigint - 1 + 3600, $2::bigint) " <>
          @series,
        [min, max]
      )

  defp in_zone(repo, zone, sql, params) do
    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone', $1, true)", [zone], log: false)
        repo.query!(sql, params, log: false).rows
      end)

    rows
  end
end
