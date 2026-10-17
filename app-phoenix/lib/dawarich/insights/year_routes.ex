defmodule Dawarich.Insights.YearRoutes do
  @moduledoc false
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Analytics.Period

  @tracks """
  FROM tracks WHERE user_id=$1
    AND start_at >= (make_timestamptz($2,1,1,0,0,0,$3) AT TIME ZONE 'UTC')
    AND start_at < (make_timestamptz($2+1,1,1,0,0,0,$3) AT TIME ZONE 'UTC')
    AND ($4::timestamptz IS NULL OR start_at >= (($4 AT TIME ZONE $3 - interval '1 year') AT TIME ZONE $3 AT TIME ZONE 'UTC'))
  """

  def fetch(subject, year, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(subject, %{"year" => year}, :year, opts),
         true <- period.year in 1..9998 do
      if period.restricted and period.year < elem(period.cutoff, 0) do
        {:ok, %{lines: []}}
      else
        fetch_admitted(subject, scope, period, year, opts)
      end
    else
      false -> {:error, :invalid_input}
      error -> error
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp fetch_admitted(subject, scope, period, year, opts) do
    signature = signature(scope, period)
    key = "dawarich:native:year_routes:" <> signature

    result =
      case command(opts, ["GET", key]) do
        {:ok, bytes} when is_binary(bytes) -> decode(bytes)
        _ -> :miss
      end

    {lines, ttl} =
      case result do
        {:hit, lines} -> {lines, nil}
        :miss -> read(scope, period, opts)
      end

    with {:ok, fresh, current} <- Period.admit(subject, %{"year" => year}, :year, opts),
         true <- signature(fresh, current) == signature do
      if ttl, do: command(opts, ["SET", key, Jason.encode!(lines), "EX", to_string(ttl)])
      {:ok, %{lines: lines}}
    else
      false -> {:error, :stale}
      error -> error
    end
  end

  def any?(scope, period) do
    [[count]] = Repo.query!("SELECT count(*) " <> @tracks, args(scope, period), log: false).rows
    count > 0
  end

  def query(scope, period) do
    Enum.reduce_while([1, 4, 16], [], fn step, _ ->
      sql = """
      SELECT ST_AsGeoJSON(ST_Simplify(geom,
        GREATEST(ST_XMax(geom)-ST_XMin(geom),ST_YMax(geom)-ST_YMin(geom))*$5/400.0),4)
      FROM (SELECT ST_Collect(original_path ORDER BY id) AS geom #{@tracks}) AS routes
      """

      [[json]] = Repo.query!(sql, args(scope, period) ++ [step * 1.0], log: false).rows
      result = if json, do: lines(Jason.decode!(json)), else: []
      if coordinate_count(result) <= 4000, do: {:halt, result}, else: {:cont, result}
    end)
    |> within_cap()
  end

  def lines(%{"type" => "LineString", "coordinates" => line}),
    do: if(length(line) > 1, do: [line], else: [])

  def lines(%{"type" => "MultiLineString", "coordinates" => lines}),
    do: Enum.filter(lines, &(length(&1) > 1))

  def lines(%{"type" => "GeometryCollection", "geometries" => geometries}),
    do: Enum.flat_map(geometries, &lines/1)

  def lines(_), do: []

  def within_cap(lines) do
    if coordinate_count(lines) <= 4000 do
      lines
    else
      {kept, _} =
        lines
        |> Enum.sort_by(&(-length(&1)))
        |> Enum.reduce({[], 4000}, fn line, {kept, budget} ->
          if length(line) <= budget,
            do: {[line | kept], budget - length(line)},
            else: {kept, budget}
        end)

      Enum.reverse(kept)
    end
  end

  defp signature(scope, period) do
    [[updated, count]] =
      Repo.query!("SELECT max(updated_at),count(*) " <> @tracks, args(scope, period), log: false).rows

    {scope.user.id, period.year, period.zone, updated, count, period.cutoff,
     if(period.restricted, do: period.now), Dawarich.Accounts.Principal.version(scope.user)}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp args(scope, period),
    do: [scope.user.id, period.year, period.zone, if(period.restricted, do: period.now)]

  defp read(scope, period, opts) do
    {Keyword.get(opts, :read, &query/2).(scope, period) || [], 86400}
  rescue
    _ -> {[], 3600}
  end

  defp coordinate_count(lines), do: Enum.sum(Enum.map(lines, &length/1))

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, lines} when is_list(lines) -> {:hit, lines}
      _ -> :miss
    end
  end

  defp command(opts, args), do: Keyword.get(opts, :command, &Redis.cache_command/1).(args)
end
