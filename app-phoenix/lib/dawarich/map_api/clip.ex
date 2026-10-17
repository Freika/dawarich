defmodule Dawarich.MapApi.Clip do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.MapApi.{Params, PointRecord, Segments}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @summary """
  SELECT ST_AsGeoJSON(path), ST_Length(path::geography), start_timestamp, end_timestamp FROM (
    SELECT ST_LineMerge(ST_Collect(ST_MakeLine(previous_position, position))) AS path,
      MIN(previous_timestamp) AS start_timestamp, MAX(timestamp) AS end_timestamp FROM (
      SELECT import_id, timestamp, lonlat::geometry AS position,
        LAG(import_id) OVER sequence AS previous_import_id,
        LAG(lonlat::geometry) OVER sequence AS previous_position,
        LAG(timestamp) OVER sequence AS previous_timestamp
      FROM points WHERE user_id = $1 AND track_id = $2 AND lonlat IS NOT NULL
        AND (anomaly = false OR anomaly IS NULL)
        AND ($3::bigint IS NULL OR timestamp >= $3::bigint) AND ($4::bigint IS NULL OR timestamp <= $4::bigint)
      WINDOW sequence AS (ORDER BY timestamp, id)
    ) ordered_points WHERE previous_position IS NOT NULL
      AND ($5::bigint IS NULL OR (import_id = $5::bigint AND previous_import_id = $5::bigint))
  ) clipped_path
  """

  def apply(feature, track, user, params, now) do
    import? = Ruby.present?(params["import_id"])

    with {:ok, range} <- range(params, now) do
      if import? or outside?(track, range),
        do: clip(feature, track, user, range, params["import_id"], import?),
        else: {:ok, feature}
    end
  end

  defp range(params, now) do
    if Ruby.present?(params["start_at"]) and Ruby.present?(params["end_at"]),
      do: Params.safe_range(params["start_at"], params["end_at"], now),
      else: {:ok, nil}
  end

  defp outside?(_track, nil), do: false

  defp outside?(track, {from, to}),
    do:
      trunc(Segments.epoch(track["start_at"])) < from or
        trunc(Segments.epoch(track["end_at"])) > to

  defp clip(feature, track, user, range, import, import?) do
    {from, to} = range || {nil, nil}
    import = if import?, do: if(import =~ ~r/\A\d+\z/, do: String.to_integer(import), else: -1)

    case Repo.query!(@summary, [user.id, track["id"], from, to, import]).rows do
      [[nil, _, _, _]] -> if import?, do: :empty_not_found, else: {:ok, feature}
      [[json, distance, start, stop]] -> {:ok, update(feature, json, distance, start, stop, user)}
    end
  end

  defp update({:object, fields}, json, distance, start, stop, user) do
    {:ok, from} = RailsTime.iso8601(naive(start), user.timezone)
    {:ok, to} = RailsTime.iso8601(naive(stop), user.timezone)
    geometry = PointRecord.ordered_json(json)
    duration = stop - start

    changes = %{
      "start_at" => from,
      "end_at" => to,
      "duration" => duration,
      "distance" => round(distance),
      "avg_speed" => if(duration > 0, do: distance * 3.6 / duration, else: 0.0),
      "segments" => [],
      "mode_timeline" => []
    }

    {:object,
     Enum.map(fields, fn
       {"geometry", _} ->
         {"geometry", geometry}

       {"properties", {:object, properties}} ->
         {"properties",
          {:object,
           Enum.map(properties, fn {key, value} -> {key, Map.get(changes, key, value)} end)}}

       pair ->
         pair
     end)}
  end

  defp naive(epoch), do: epoch |> DateTime.from_unix!() |> DateTime.to_naive()
end
