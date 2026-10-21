defmodule Dawarich.Digests.Queries do
  @moduledoc false

  @columns "SELECT id, user_id, year, month, distance, flight_distance, daily_distance, toponyms FROM public.stats"

  def monthly(repo, context, year, month) do
    rows(repo, @columns <> " WHERE user_id = $1 AND year = $2 AND month = $3 LIMIT 1", [
      context.user_id,
      year,
      month
    ])
    |> List.first()
  end

  def yearly(repo, context, year), do: select(repo, context, year, true)
  def history(repo, context), do: select(repo, context, nil, false)

  def distance(repo, context) do
    {scope, params} = scope(context, 2)

    %{rows: [[distance]]} =
      repo.query!(
        "SELECT coalesce(sum(distance), 0)::text FROM public.stats WHERE user_id = $1" <> scope,
        [context.user_id | params],
        log: false
      )

    distance
  end

  defp select(repo, context, year, scoped?) do
    {where, params} =
      if year, do: {" AND year = $2", [context.user_id, year]}, else: {"", [context.user_id]}

    {scope, cutoff} = if scoped?, do: scope(context, length(params) + 1), else: {"", []}
    order = if year, do: "month", else: "id"

    rows(
      repo,
      @columns <> " WHERE user_id = $1" <> where <> scope <> " ORDER BY #{order}",
      params ++ cutoff
    )
  end

  defp scope(%{stat_cutoff: nil}, _offset), do: {"", []}

  defp scope(%{stat_cutoff: {year, month}}, offset),
    do:
      {" AND (year > $#{offset} OR (year = $#{offset} AND month >= $#{offset + 1}))",
       [year, month]}

  defp rows(repo, sql, params) do
    result = repo.query!(sql, params, log: false)
    Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
  end
end
