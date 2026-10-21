defmodule Dawarich.Points.AnomalyFilter.Query do
  @moduledoc false
  @columns "id,timestamp,tracker_id,ST_X(lonlat::geometry),ST_Y(lonlat::geometry),accuracy"

  def month_end(context, first) do
    [[last]] =
      context.repo.query!(
        "SELECT extract(epoch FROM ((date_trunc('month',to_timestamp($1) AT TIME ZONE $2) + interval '1 month' - interval '1 second') AT TIME ZONE $2))::bigint",
        [first, context.zone],
        log: false
      ).rows

    last
  end

  def context(context, first, last) do
    before =
      fetch(
        context,
        "timestamp < $2 AND timestamp >= $3 ORDER BY timestamp DESC,id DESC LIMIT 240",
        [first, first - 3600]
      )

    before =
      if length(before) < 5,
        do: fetch(context, "timestamp < $2 ORDER BY timestamp DESC,id DESC LIMIT 5", [first]),
        else: before

    before = Enum.reverse(before)

    main =
      fetch(context, "timestamp BETWEEN $2 AND $3 ORDER BY timestamp,id", [
        first,
        last
      ])

    after_ctx = fetch(context, "timestamp > $2 ORDER BY timestamp,id LIMIT 5", [last])
    {before ++ main ++ after_ctx, Enum.filter(before, &(&1.timestamp >= first - 3600)) ++ main}
  end

  def speeds(_context, points) when length(points) < 3, do: %{}

  def speeds(context, points) do
    context.repo.query!(
      """
      WITH ordered_points AS (
        SELECT id,lonlat,timestamp,LAG(id) OVER per_device AS prev_id,
          LAG(lonlat) OVER per_device AS prev_lonlat,LAG(timestamp) OVER per_device AS prev_timestamp
        FROM points WHERE id=ANY($1::bigint[])
        WINDOW per_device AS (PARTITION BY COALESCE(tracker_id,'') ORDER BY timestamp,id))
      SELECT id,prev_id,ST_Distance(lonlat::geography,prev_lonlat::geography),timestamp-prev_timestamp
      FROM ordered_points WHERE prev_id IS NOT NULL
      """,
      [Enum.map(points, & &1.id)],
      log: false
    ).rows
    |> Enum.reduce(%{}, fn [id, prev, meters, seconds], acc ->
      speed = speed(meters, seconds)

      acc
      |> Map.update(prev, %{outgoing: speed}, &Map.put(&1, :outgoing, speed))
      |> Map.update(id, %{incoming: speed}, &Map.put(&1, :incoming, speed))
    end)
  end

  defp speed(nil, _), do: nil
  defp speed(_, nil), do: nil
  defp speed(meters, seconds) when seconds > 0, do: meters / seconds
  defp speed(meters, _), do: if(meters > 1000, do: :infinity, else: nil)

  defp fetch(context, condition, params) do
    context.repo.query!(
      "SELECT #{@columns} FROM points WHERE user_id=$1 AND anomaly IS NOT TRUE AND #{condition}",
      [context.user_id | params],
      log: false
    ).rows
    |> Enum.map(fn [id, at, tracker, longitude, latitude, accuracy] ->
      %{
        id: id,
        timestamp: at,
        tracker: tracker || "",
        coords: {latitude, longitude},
        accuracy: accuracy
      }
    end)
  end
end
