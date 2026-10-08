defmodule Dawarich.MapApi.TrackRecord do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.MapApi.Segments

  def rows(where, args) do
    result =
      Repo.query!(
        "SELECT t.id, t.start_at, t.end_at, t.distance, t.avg_speed, t.duration, t.lock_version, t.dominant_mode, " <>
          RailsTime.sql("t.start_at", 0) <>
          " AS start_text, " <>
          RailsTime.sql("t.end_at", 0) <>
          " AS end_text, " <>
          coordinates("t.original_path") <> " AS coordinates FROM tracks t " <> where,
        args
      )

    records(result)
  end

  def features(rows, full?) do
    segments = rows |> Enum.map(& &1["id"]) |> segments(full?)
    Enum.map(rows, &feature(&1, Map.get(segments, &1["id"], []), full?))
  end

  defp feature(row, segments, full?) do
    properties = [
      {"id", row["id"]},
      {"color", "#6366F1"},
      {"start_at", row["start_text"]},
      {"end_at", row["end_text"]},
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

  defp coordinates(column) do
    "CASE WHEN #{column} IS NULL THEN NULL ELSE COALESCE((SELECT jsonb_agg(jsonb_build_array(" <>
      "ST_X((d).geom)::float8, ST_Y((d).geom)::float8) ORDER BY (d).path) FROM ST_DumpPoints(#{column}) d), " <>
      "'[]'::jsonb) END"
  end

  defp segments([], _full?), do: %{}

  defp segments(ids, full?) do
    details =
      if full?,
        do:
          ", s.distance, s.duration, s.avg_speed, s.confidence, " <>
            coordinates("s.path") <> " AS coordinates",
        else: ""

    Repo.query!(
      "SELECT s.track_id, s.id, s.start_at, s.end_at, s.start_index, s.end_index, s.transportation_mode" <>
        details <> " FROM track_segments s WHERE s.track_id = ANY($1) ORDER BY s.track_id, s.id",
      [ids]
    )
    |> records()
    |> Enum.group_by(& &1["track_id"])
  end

  defp records(result) do
    for row <- result.rows do
      record = result.columns |> Enum.zip(row) |> Map.new()

      if Map.has_key?(record, "coordinates"),
        do: Map.update!(record, "coordinates", &floats/1),
        else: record
    end
  end

  defp floats(nil), do: nil
  defp floats(pairs), do: Enum.map(pairs, fn pair -> Enum.map(pair, &(&1 * 1.0)) end)
end
