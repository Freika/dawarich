defmodule Dawarich.Ingest.GeoJSON do
  @moduledoc false

  alias Dawarich.Ingest.{Geo, Permit, Ruby, Timestamp}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support

  @motion ~w(motion activity action departure_date)

  def points(params, user_id), do: points(params, user_id, false)

  def points(params, user_id, native?) do
    case params |> Permit.geojson() |> Map.get("locations") do
      list when is_list(list) ->
        list |> Enum.map(&point(&1, user_id, native?)) |> Enum.reject(&is_nil/1)

      _other ->
        Ruby.unsupported!("locations is not an array")
    end
  end

  def overland(params), do: overland(params, false)

  def overland(params, native?) do
    locations =
      case params |> Permit.geojson() |> Map.get("locations") do
        nil -> []
        map when is_map(map) -> [map]
        list -> list
      end

    locations |> Enum.map(&overland_point(&1, native?)) |> Enum.reject(&is_nil/1)
  end

  defp point(location, user_id, native?) do
    timestamp = timestamp(Ruby.dig(location, ["properties", "timestamp"]), native?)
    coordinates = Ruby.dig(location, ["geometry", "coordinates"])

    if Ruby.present?(coordinates) and timestamp != nil and
         not Geo.null_island?(Ruby.at(coordinates, 0), Ruby.at(coordinates, 1)) do
      properties = location["properties"]

      common(
        location,
        properties,
        timestamp,
        Geo.wkt(Ruby.at(coordinates, 0), Ruby.at(coordinates, 1))
      )
      |> Map.merge(%{
        course_accuracy: safe_decimal(properties["course_accuracy"]),
        course: safe_decimal(properties["course"]),
        user_id: user_id
      })
    end
  end

  defp overland_point(point, native?) do
    timestamp = timestamp(Ruby.dig(point, ["properties", "timestamp"]), native?)

    if point["geometry"] != nil and timestamp != nil do
      coordinates = Ruby.dig(point, ["geometry", "coordinates"])

      lonlat =
        if Ruby.blank?(coordinates),
          do: nil,
          else: Geo.wkt(Ruby.at(coordinates, 0), Ruby.at(coordinates, 1))

      common(point, point["properties"], timestamp, lonlat)
    end
  end

  defp timestamp(value, true), do: Dawarich.Ingest.Closure.timestamp(value, :points)
  defp timestamp(value, false), do: Timestamp.points(value)

  defp common(location, properties, timestamp, lonlat) do
    %{
      lonlat: lonlat,
      battery_status: properties["battery_state"],
      battery: battery(properties["battery_level"]),
      timestamp: timestamp,
      altitude: properties["altitude"],
      tracker_id: properties["device_id"],
      velocity: properties["speed"],
      ssid: properties["wifi"],
      accuracy: properties["horizontal_accuracy"],
      vertical_accuracy: properties["vertical_accuracy"],
      motion_data:
        for(key <- @motion, Ruby.truthy?(properties[key]), into: %{}, do: {key, properties[key]}),
      raw_data: location,
      altitude_decimal: properties["altitude"]
    }
  end

  defp battery(level) do
    value = trunc(Ruby.to_f(level) * 100)
    if value > 0, do: value
  end

  defp safe_decimal(nil), do: nil

  defp safe_decimal(value) do
    number =
      cond do
        is_number(value) -> value * 1.0
        is_binary(value) -> Support.float(value)
        true -> nil
      end

    if is_float(number) and abs(number) < 1_000, do: value
  end
end
