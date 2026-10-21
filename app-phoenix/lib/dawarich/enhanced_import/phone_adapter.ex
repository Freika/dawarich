defmodule Dawarich.EnhancedImport.PhoneAdapter do
  @moduledoc false
  alias Dawarich.EnhancedImport.AdapterFields, as: Fields
  alias Dawarich.Imports.JsonStream
  @source "google_phone_takeout"

  def reduce(path, import, context, acc, fun) do
    {acc, profile} =
      JsonStream.reduce(
        path,
        {acc, nil},
        fn
          {:value, [index, "semanticSegments"], value, _, _}, {acc, profile}
          when is_integer(index) ->
            {emit_segment(Fields.plain(value), import, context, acc, fun), profile}

          {:value, ["userLocationProfile"], value, _, _}, {acc, _profile} ->
            {acc, Fields.plain(value)}

          _, state ->
            state
        end,
        fn
          [index, "semanticSegments"] when is_integer(index) -> true
          ["userLocationProfile"] -> true
          _ -> false
        end,
        mode: :phone_saj
      )

    places = if is_map(profile), do: profile["frequentPlaces"] || [], else: []
    Enum.reduce(places, acc, fn place, acc -> Fields.emit(frequent_place(place), acc, fun) end)
  end

  defp emit_segment(segment, import, context, acc, fun) when is_map(segment) do
    first = Fields.time(segment["startTime"], context)
    last = Fields.time(segment["endTime"], context)
    acc = Fields.emit(visit(segment["visit"], first, last), acc, fun)
    Fields.emit(track(segment["activity"], import, first, last), acc, fun)
  end

  defp emit_segment(_, _, _, acc, _), do: acc

  defp visit(visit, first, last) do
    unless is_nil(visit) or is_map(visit), do: raise(ArgumentError, "Visit must be an object")
    candidate = if is_map(visit), do: visit["topCandidate"]

    if Fields.presence(candidate) && first && last do
      case Fields.coordinates(get_in(candidate, ["placeLocation", "latLng"])) do
        {lat, lon} ->
          place =
            Fields.place(
              "google:#{candidate["placeId"]}",
              Fields.humanize(candidate["semanticType"]) || "Unknown",
              lat,
              lon,
              candidate["semanticType"]
            )

          Fields.visit(place, first, last, candidate["probability"], @source)

        nil ->
          nil
      end
    end
  end

  defp track(activity, import, first, last) do
    if Fields.presence(activity) do
      candidate = activity["topCandidate"]

      if candidate do
        Fields.track(
          import,
          first,
          last,
          candidate["type"],
          activity["distanceMeters"],
          candidate["probability"],
          @source
        )
      end
    end
  end

  defp frequent_place(place) do
    if Fields.presence(place) && Fields.presence(place["placeId"]) do
      coords = Fields.coordinates(place["placeLocation"]) || e7_pair(place)

      if coords do
        {lat, lon} = coords

        Fields.place(
          "google:#{place["placeId"]}",
          Fields.presence(place["label"]) || Fields.presence(place["name"]) || "Frequent place",
          lat,
          lon,
          place["semanticType"] || "FREQUENT_PLACE"
        )
      end
    end
  end

  defp e7_pair(place) do
    lat = Fields.e7(place["latitudeE7"])
    lon = Fields.e7(place["longitudeE7"])
    if lat && lon, do: {lat, lon}
  end
end
