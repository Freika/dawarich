defmodule Dawarich.Posters.TrackBuilder do
  @moduledoc false
  alias Dawarich.Posters.Time
  alias Dawarich.Repo

  def build(user_id, settings, repo \\ Repo) do
    first = Time.parse(settings["start_at"])
    last = Time.parse(settings["end_at"])

    segments =
      if settings["source"] == "tracks" do
        repo.query!(
          "SELECT ST_AsGeoJSON(original_path)::json->'coordinates' FROM tracks WHERE user_id=$1 AND (start_at <= $3 OR $3 IS NULL) AND (end_at >= $2 OR $2 IS NULL) ORDER BY start_at ASC",
          [user_id, first, last]
        ).rows
        |> Enum.map(&hd/1)
      else
        repo.query!(
          "SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry),timestamp FROM points WHERE user_id=$1 AND (anomaly=false OR anomaly IS NULL) AND timestamp BETWEEN $2::bigint AND $3::bigint ORDER BY timestamp ASC",
          [user_id, Time.epoch(first), Time.epoch(last)]
        ).rows
        |> split()
      end

    geometry(segments)
  end

  def geometry(segments) do
    case Enum.filter(segments, &(length(&1) >= 2)) do
      [] -> nil
      segments -> %{"type" => "MultiLineString", "coordinates" => segments}
    end
  end

  defp split([]), do: []

  defp split([first | rest]) do
    {groups, current, _} =
      Enum.reduce(rest, {[], [first], first}, fn row, {groups, current, previous} ->
        if Enum.at(row, 2) - Enum.at(previous, 2) > 3600,
          do: {[Enum.reverse(current) | groups], [row], row},
          else: {groups, [row | current], row}
      end)

    [Enum.reverse(current) | groups]
    |> Enum.reverse()
    |> Enum.map(fn rows -> Enum.map(rows, &Enum.take(&1, 2)) end)
  end
end
