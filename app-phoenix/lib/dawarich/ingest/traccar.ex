defmodule Dawarich.Ingest.Traccar do
  @moduledoc false

  alias Dawarich.Ingest.{Geo, Permit, Ruby, Timestamp}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support

  @false_values [false, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def payloads(params) do
    raw = Permit.traccar(params)

    form? =
      Ruby.blank?(raw["location"]) and Ruby.present?(raw["lat"]) and Ruby.present?(raw["lon"])

    payload = if form?, do: form(raw), else: raw
    location = payload["location"] || %{}
    coords = presence(location["coords"]) || location

    if Ruby.present?(coords) and Ruby.present?(coords["latitude"]) and
         Ruby.present?(coords["longitude"]) and
         Ruby.present?(location["timestamp"]),
       do: build(raw, payload, location, coords, form?),
       else: []
  end

  defp build(raw, payload, location, coords, form?) do
    lon = coordinate(coords["longitude"], -180.0, 180.0)
    lat = coordinate(coords["latitude"], -90.0, 90.0)
    timestamp = if lon && lat, do: Timestamp.traccar(location["timestamp"])

    if is_nil(lon) or is_nil(lat) or is_nil(timestamp) do
      []
    else
      battery = presence(location["battery"]) || payload["battery"] || %{}

      [
        %{
          lonlat: Geo.wkt(lon, lat),
          timestamp: timestamp,
          altitude: coords["altitude"],
          accuracy: coords["accuracy"],
          velocity: if(coords["speed"] == nil, do: nil, else: Ruby.to_s(coords["speed"])),
          tracker_id: payload["device_id"],
          battery: level(raw, battery, form?),
          battery_status: status(battery),
          motion_data: motion(payload),
          raw_data: raw,
          altitude_decimal: coords["altitude"]
        }
      ]
    end
  end

  defp coordinate(raw, min, max) do
    case Support.float(Ruby.to_s(raw)) do
      value when is_float(value) and value >= min and value <= max -> value
      _ -> nil
    end
  end

  defp level(raw, _battery, true), do: positive(raw["batt"] && Ruby.to_i(raw["batt"]))

  defp level(_raw, battery, false),
    do: positive(battery["level"] && trunc(Ruby.to_f(battery["level"]) * 100))

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp status(battery) do
    cond do
      not Map.has_key?(battery, "is_charging") -> "unknown"
      Ruby.truthy?(battery["is_charging"]) -> "charging"
      true -> "unplugged"
    end
  end

  defp motion(payload) do
    location = payload["location"] || %{}
    activity = Enum.find([payload["activity"], location["activity"]], &Ruby.truthy?/1) || %{}

    [
      {"activity", activity["type"], Ruby.truthy?(activity["type"])},
      {"is_moving", location["is_moving"], location["is_moving"] != nil},
      {"event", location["event"], Ruby.truthy?(location["event"])}
    ]
    |> Enum.filter(&elem(&1, 2))
    |> Map.new(fn {key, value, _} -> {key, value} end)
  end

  defp form(raw) do
    %{
      "device_id" => raw["id"],
      "location" => %{
        "timestamp" => raw["timestamp"],
        "latitude" => raw["lat"],
        "longitude" => raw["lon"],
        "accuracy" => raw["accuracy"],
        "altitude" => raw["altitude"],
        "speed" => if(Ruby.present?(raw["speed"]), do: Ruby.to_f(raw["speed"]) / 1.94384),
        "heading" => raw["bearing"],
        "event" => raw["alarm"]
      },
      "battery" => charging(raw["charge"])
    }
  end

  defp charging(nil), do: %{}
  defp charging(""), do: %{}
  defp charging(value) when is_number(value), do: %{"is_charging" => value != 0}
  defp charging(value), do: %{"is_charging" => value not in @false_values}

  defp presence(value), do: if(Ruby.present?(value), do: value)
end
