defmodule Dawarich.Imports.ActivityBackfill.Semantic do
  @moduledoc false
  alias Dawarich.Imports.GoogleRecords.Point
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Imports.JsonStream.Section
  alias Dawarich.Ingest.Ruby

  def run(repo, import_id, path, context) do
    case Section.last(path, "timelineObjects") do
      {%{kind: :object}, %{kind: :array} = section} ->
        Section.reduce(path, section, :ok, fn object, :ok ->
          object |> plain() |> process(repo, import_id, context)
          :ok
        end)

      _ ->
        :ok
    end
  rescue
    error in JsonStream.Error ->
      if error.reason == :syntax, do: :ok, else: reraise(error, __STACKTRACE__)
  end

  def timestamp(value, _context) when value in [nil, false], do: nil
  def timestamp(value, context), do: Point.timestamp(value, context)

  def plain({:object, pairs}), do: Map.new(pairs, fn {key, value} -> {key, plain(value)} end)
  def plain(values) when is_list(values), do: Enum.map(values, &plain/1)
  def plain(value), do: value

  defp process(%{"activitySegment" => segment}, repo, import_id, context) when is_map(segment) do
    motion =
      Enum.reduce(["activities", "activityType"], %{}, fn key, acc ->
        put_truthy(acc, key, segment[key])
      end)
      |> put_truthy("travelMode", dig(segment["waypointPath"], "travelMode"))

    if map_size(motion) > 0 do
      first = timestamp(dig(segment["duration"], "startTimestamp"), context)
      last = timestamp(dig(segment["duration"], "endTimestamp"), context)
      if first && last, do: update(repo, import_id, first, last, motion)
    end
  end

  defp process(_object, _repo, _import_id, _context), do: :ok

  defp update(repo, import_id, first, last, motion) do
    points =
      repo.query!(
        "SELECT id,motion_data FROM points WHERE import_id=$1 AND timestamp >= $2 AND timestamp <= $3 ORDER BY id",
        [import_id, first, last],
        log: false
      ).rows

    for [id, previous] <- points do
      if not (is_nil(previous) or is_map(previous)),
        do: raise(ArgumentError, "motion_data does not support merge")

      repo.query!(
        "UPDATE points SET motion_data=COALESCE(motion_data,'{}'::jsonb) || $2::jsonb WHERE id=$1",
        [id, motion],
        log: false
      )
    end
  end

  defp dig(nil, _key), do: nil
  defp dig(map, key) when is_map(map), do: map[key]
  defp dig(_value, _key), do: raise(ArgumentError, "activity field does not support dig")

  defp put_truthy(acc, key, value),
    do: if(Ruby.truthy?(value), do: Map.put(acc, key, value), else: acc)
end
