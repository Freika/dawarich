defmodule Dawarich.Imports.GoogleSemanticPoints do
  @moduledoc false
  alias Dawarich.Imports.GoogleRecords.Point
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def prepare(object, context) do
    activity = field(object, "activitySegment")
    visit = field(object, "placeVisit")

    cond do
      Ruby.present?(activity) -> activity(activity, context)
      Ruby.present?(visit) -> visit(visit, context)
      true -> []
    end
  rescue
    e in Value.Error -> raise ArgumentError, Exception.message(e)
  end

  defp activity(activity, context) do
    start = field(activity, "startLocation")

    if Ruby.blank?(start) do
      path = field(activity, "waypointPath")

      if Ruby.blank?(path) do
        []
      else
        waypoints = field(path, "waypoints")

        unless is_list(waypoints),
          do: raise(ArgumentError, "undefined method 'map' for #{Value.instance(waypoints)}")

        Enum.map(
          waypoints,
          &point(field(&1, "lngE7"), field(&1, "latE7"), nil, activity, context)
        )
      end
    else
      [
        point(
          field(start, "longitudeE7"),
          field(start, "latitudeE7"),
          field(start, "accuracyMetres"),
          activity,
          context
        )
      ]
    end
  end

  defp visit(visit, context) do
    location = field(visit, "location")

    if location && Ruby.present?(field(location, "latitudeE7")) &&
         Ruby.present?(field(location, "longitudeE7")) do
      [
        point(
          field(location, "longitudeE7"),
          field(location, "latitudeE7"),
          field(location, "accuracyMetres"),
          visit,
          context
        )
      ]
    else
      case field(visit, "otherCandidateLocations") do
        [candidate | _] ->
          if Ruby.present?(field(candidate, "latitudeE7")) &&
               Ruby.present?(field(candidate, "longitudeE7")),
             do: [
               point(
                 field(candidate, "longitudeE7"),
                 field(candidate, "latitudeE7"),
                 field(candidate, "accuracyMetres"),
                 visit,
                 context
               )
             ],
             else: []

        _ ->
          []
      end
    end
  end

  defp point(lon, lat, accuracy, data, context) do
    duration = field(data, "duration")
    timestamp = field(duration, "startTimestamp")

    timestamp =
      if Ruby.truthy?(timestamp), do: timestamp, else: field(duration, "startTimestampMs")

    motion =
      Map.new(
        for key <- ~w(activities activityType),
            value = field(data, key),
            Ruby.truthy?(value),
            do: {key, plain(value)}
      )

    path = field(data, "waypointPath")
    mode = if is_nil(path), do: nil, else: field(path, "travelMode")
    motion = if Ruby.truthy?(mode), do: Map.put(motion, "travelMode", plain(mode)), else: motion

    %{
      lonlat: "POINT(#{Value.to_s(float(lon))} #{Value.to_s(float(lat))})",
      timestamp: Point.timestamp(timestamp, context),
      accuracy: accuracy,
      motion_data: motion
    }
  end

  defp float(nil), do: 0.0
  defp float(value) when is_number(value) or is_binary(value), do: Ruby.to_f(value) / 10_000_000

  defp float(value),
    do: raise(ArgumentError, "undefined method 'to_f' for #{Value.instance(value)}")

  defp field(value, key), do: Value.index(value, key)
  defp plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
end
