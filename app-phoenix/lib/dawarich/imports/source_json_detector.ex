defmodule Dawarich.Imports.SourceJsonDetector do
  @moduledoc false
  alias Dawarich.Imports.JsonStream

  @rules [
    {:mobile_photo_library, ~w(type version points),
     [["points", 0, "timestamp"], ["points", 0, "latitude"], ["points", 0, "longitude"]]},
    {:google_semantic_history, ["timelineObjects"],
     [["timelineObjects", 0, "activitySegment"], ["timelineObjects", 0, "placeVisit"]]},
    {:google_records, ["locations"],
     [["locations", 0, "latitudeE7"], ["locations", 0, "longitudeE7"]]},
    {:google_phone_takeout, [], []},
    {:google_photos, ~w(title creationTime imageViews), [["creationTime", "timestamp"]]},
    {:geojson, ~w(type features),
     [["features", 0, "type"], ["features", 0, "geometry"], ["features", 0, "properties"]]},
    {:polarsteps, [], []}
  ]

  def detect(bytes, raw) do
    value = parse(bytes)

    Enum.find_value(@rules, fn {source, keys, paths} ->
      if matches?(value, source, keys, paths), do: source
    end) || raw_source(raw)
  end

  defp parse(bytes) do
    case decode(bytes) do
      {:ok, value} ->
        value

      :error ->
        Enum.reduce_while(["]", "}]", "}}]"], nil, fn suffix, _ ->
          case decode(bytes <> suffix) do
            {:ok, value} -> {:halt, value}
            :error -> {:cont, nil}
          end
        end)
    end
  end

  defp decode(bytes) do
    value =
      JsonStream.reduce(
        {:bytes, bytes},
        nil,
        fn
          {:value, [], value, _, _}, _ -> materialize(value)
          _, acc -> acc
        end,
        fn path -> path == [] end,
        mode: :compat
      )

    {:ok, value}
  rescue
    JsonStream.Error -> :error
  end

  defp materialize({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, materialize(v)} end)
  defp materialize(list) when is_list(list), do: Enum.map(list, &materialize/1)
  defp materialize(value), do: value

  defp matches?(value, :google_phone_takeout, _, _) do
    (keys?(value, ["semanticSegments"]) && present?(value, ["semanticSegments", 0, "startTime"])) ||
      keys?(value, ["rawSignals"]) ||
      (is_list(value) &&
         Enum.any?(
           [[0, "visit", "topCandidate", "placeLocation"], [0, "activity"], [0, "timelinePath"]],
           &present?(value, &1)
         ))
  end

  defp matches?(value, :polarsteps, _, _) do
    (keys?(value, ["locations"]) &&
       Enum.any?(
         [["locations", 0, "lat"], ["locations", 0, "lon"], ["locations", 0, "time"]],
         &present?(value, &1)
       )) ||
      (is_list(value) && Enum.any?([[0, "arrived"], [0, "departed"]], &present?(value, &1)))
  end

  defp matches?(value, source, keys, paths) do
    keys?(value, keys) && values?(value, source) && Enum.any?(paths, &present?(value, &1))
  end

  defp keys?(map, keys) when is_map(map), do: Enum.all?(keys, &Map.has_key?(map, &1))
  defp keys?(_, _), do: false

  defp values?(value, :mobile_photo_library),
    do: value["type"] == "DawarichPhotoLibrary" && value["version"] == 1

  defp values?(value, :geojson), do: value["type"] == "FeatureCollection"
  defp values?(_, _), do: true
  defp present?(value, []), do: not is_nil(value)

  defp present?(value, [key | rest]) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, value} -> present?(value, rest)
      :error -> false
    end
  end

  defp present?(value, [key | rest]) when is_list(value) and is_integer(key),
    do: key >= 0 && key < length(value) && present?(Enum.at(value, key), rest)

  defp present?(_, _), do: false

  defp raw_source(raw) do
    cond do
      includes?(raw, [~s("DawarichPhotoLibrary"), ~s("points")]) &&
          Regex.match?(~r/"version"\s*:\s*1\b/, raw) ->
        :mobile_photo_library

      includes?(raw, [~s("semanticSegments")]) && any?(raw, ~w(startTime visit activity)) ->
        :google_phone_takeout

      includes?(raw, [~s("timelineObjects")]) && any?(raw, ~w(activitySegment placeVisit)) ->
        :google_semantic_history

      includes?(raw, [~s("locations"), ~s("latitudeE7")]) ->
        :google_records

      includes?(raw, [~s("FeatureCollection"), ~s("features")]) ->
        :geojson

      includes?(raw, [~s("rawSignals")]) ->
        :google_phone_takeout

      includes?(raw, [~s("timelinePath")]) && any?(raw, ~w(startTime endTime)) ->
        :google_phone_takeout

      includes?(raw, [~s("topCandidate"), ~s("placeLocation")]) ->
        :google_phone_takeout

      includes?(raw, [~s("title"), ~s("imageViews"), ~s("creationTime")]) ->
        :google_photos

      includes?(raw, [~s("arrived"), ~s("departed"), ~s("segment-)]) ->
        :polarsteps

      true ->
        nil
    end
  end

  defp includes?(raw, terms), do: Enum.all?(terms, &String.contains?(raw, &1))
  defp any?(raw, keys), do: Enum.any?(keys, &String.contains?(raw, ~s("#{&1}")))
end
