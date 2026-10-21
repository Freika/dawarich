defmodule Dawarich.Stats.Hexagons do
  @moduledoc false

  alias Dawarich.H3
  alias Dawarich.Stats.MonthQueries

  @max_cells 10_000
  @points """
  SELECT id, ST_Y(lonlat::geometry), ST_X(lonlat::geometry), timestamp FROM points
  WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp BETWEEN $2 AND $3
    AND lonlat IS NOT NULL
    AND EXTRACT(year FROM (to_timestamp(timestamp) AT TIME ZONE $4)) = $5::int
    AND EXTRACT(month FROM (to_timestamp(timestamp) AT TIME ZONE $4)) = $6::int
    AND id > $7
  ORDER BY id LIMIT $8
  """

  def calculate(repo, user, year, month, opts \\ []) do
    resolution = Keyword.get(opts, :resolution, 8)
    {start, finish} = MonthQueries.window(year, month)
    params = [user.id, start, finish, user.zone, year, month]
    batch = Keyword.get(opts, :batch, 50_000)
    {cells, order} = collect(repo, params, min(max(resolution, 0), 15), batch, 0, {%{}, []})

    if map_size(cells) > @max_cells do
      calculate(repo, user, year, month, Keyword.put(opts, :resolution, max(resolution - 2, 0)))
    else
      order
      |> Enum.reverse()
      |> Enum.map(fn index ->
        {count, first, last} = Map.fetch!(cells, index)
        [index, count, first, last]
      end)
    end
  end

  defp collect(repo, params, resolution, batch, after_id, acc) do
    rows = repo.query!(@points, params ++ [after_id, batch], log: false).rows
    acc = Enum.reduce(rows, acc, &add(&1, &2, resolution))

    if length(rows) == batch,
      do: collect(repo, params, resolution, batch, rows |> List.last() |> hd(), acc),
      else: acc
  end

  defp add([_id, lat, lng, timestamp], {cells, order}, resolution) do
    index = H3.hex(H3.from_geo({lat, lng}, resolution))

    case cells do
      %{^index => {count, first, last}} ->
        {%{cells | index => {count + 1, min(first, timestamp), max(last, timestamp)}}, order}

      _ ->
        {Map.put(cells, index, {1, timestamp, timestamp}), [index | order]}
    end
  end
end
