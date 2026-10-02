defmodule Dawarich.MapApi.TrackRecord do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.MapApi.Segments

  def rows(where, args) do
    result =
      Repo.query!(
        "SELECT t.id, t.start_at, t.end_at, t.distance, t.avg_speed, t.duration, t.lock_version, t.dominant_mode, " <>
          coordinates("t.original_path") <> " AS coordinates FROM tracks t " <> where,
        args
      )

    records(result)
  end

  def collection(rows, zone, full?),
    do:
      {:object,
       [{"type", "FeatureCollection"}, {"features", Enum.map(rows, &feature(&1, zone, full?))}]}

  def feature(row, zone, full?) do
    {:ok, from} = RailsTime.iso8601(row["start_at"], zone)
    {:ok, to} = RailsTime.iso8601(row["end_at"], zone)
    segments = segments(row["id"])

    properties = [
      {"id", row["id"]},
      {"color", "#6366F1"},
      {"start_at", from},
      {"end_at", to},
      {"distance", row["distance"] || 0},
      {"avg_speed", row["avg_speed"] || 0.0},
      {"duration", row["duration"]},
      {"revision", row["lock_version"]},
      {"dominant_mode", Segments.mode(row["dominant_mode"])},
      {"dominant_mode_emoji", Segments.emoji(row["dominant_mode"])},
      {"mode_timeline", Segments.timeline(segments, row)}
    ]

    properties =
      if full?, do: properties ++ [{"segments", Segments.full(segments, row)}], else: properties

    {:object,
     [
       {"type", "Feature"},
       {"geometry", {:object, [{"type", "LineString"}, {"coordinates", row["coordinates"]}]}},
       {"properties", {:object, properties}}
     ]}
  end

  def coordinates(column) do
    "CASE WHEN #{column} IS NULL THEN NULL ELSE COALESCE((SELECT jsonb_agg(jsonb_build_array(" <>
      "ST_X((d).geom)::float8, ST_Y((d).geom)::float8) ORDER BY (d).path) FROM ST_DumpPoints(#{column}) d), " <>
      "'[]'::jsonb) END"
  end

  defp segments(id) do
    result =
      Repo.query!(
        "SELECT s.id, s.start_at, s.end_at, s.start_index, s.end_index, s.transportation_mode, s.distance, " <>
          "s.duration, s.avg_speed, s.confidence, " <>
          coordinates("s.path") <>
          " AS coordinates FROM track_segments s WHERE s.track_id = $1 ORDER BY s.id",
        [id]
      )

    records(result)
  end

  defp records(result) do
    for row <- result.rows do
      result.columns |> Enum.zip(row) |> Map.new() |> Map.update!("coordinates", &floats/1)
    end
  end

  defp floats(nil), do: nil
  defp floats(pairs), do: Enum.map(pairs, fn pair -> Enum.map(pair, &(&1 * 1.0)) end)
end
