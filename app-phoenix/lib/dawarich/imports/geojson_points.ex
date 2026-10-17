defmodule Dawarich.Imports.GeojsonPoints do
  @moduledoc false
  alias Dawarich.Imports.ImportTime
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number

  @aliases %{
    timestamp: ~w(timestamp time date datetime when created_at recorded_at fixTime tst),
    altitude: ~w(altitude alt ele elevation height z),
    speed: ~w(speed velocity vel speed_mps speed_kmh),
    accuracy: ~w(accuracy acc horizontal_accuracy hdop precision),
    vertical_accuracy: ~w(vertical_accuracy vac vdop),
    battery: ~w(battery batt bat battery_level bs),
    heading: ~w(heading bearing course cog),
    tracker_id: ~w(tracker_id tid device_id device deviceId)
  }

  def reduce(feature, state, fun, context) do
    if index(feature, "type") == "Feature" do
      geometry = index(feature, "geometry")

      case index(geometry, "type") do
        "Point" ->
          fun.(point(feature, context), state)

        "LineString" ->
          Enum.reduce(index(geometry, "coordinates"), state, fn p, acc ->
            fun.(line(p, context), acc)
          end)

        "MultiLineString" ->
          Enum.reduce(index(geometry, "coordinates"), state, fn points, acc ->
            Enum.reduce(points, acc, fn p, acc -> fun.(line(p, context), acc) end)
          end)

        _ ->
          state
      end
    else
      state
    end
  end

  defp point(feature, context) do
    geometry = index(feature, "geometry")
    coordinates = index(geometry, "coordinates")
    properties = index(feature, "properties")
    altitude = ruby_or(field(properties, :altitude), Enum.at(coordinates, 2))
    time = ruby_or(field(properties, :timestamp), Enum.at(coordinates, 3))

    timestamp =
      if is_number(time),
        do: trunc(if(time > 10_000_000_000, do: time / 1000, else: time)),
        else: string_time(field(properties, :timestamp), context)

    {speed, key} = field_key(properties, :speed)
    speed = if is_nil(speed), do: 0.0, else: float(speed)
    speed = if key == "speed_kmh", do: speed / 3.6, else: speed

    attrs = %{
      lonlat: wkt(coordinates),
      timestamp: timestamp,
      altitude: altitude,
      battery_status: index(properties, "battery_state"),
      battery: battery(field(properties, :battery)),
      velocity: Dawarich.RubyFloat.round(speed, 1),
      tracker_id: field(properties, :tracker_id),
      ssid: index(properties, "wifi"),
      accuracy: field(properties, :accuracy),
      vertical_accuracy: field(properties, :vertical_accuracy),
      course: field(properties, :heading),
      motion_data:
        Map.new(
          for key <- ~w(motion activity action departure_date),
              value = index(properties, key),
              Ruby.truthy?(value),
              do: {key, plain(value)}
        )
    }

    if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
  end

  defp line(p, context) do
    time = Enum.at(p, 3)

    %{
      lonlat: wkt(p),
      timestamp: if(is_number(time), do: trunc(time), else: string_time(time, context))
    }
  end

  defp wkt(p), do: "POINT(#{text(Enum.at(p, 0))} #{text(Enum.at(p, 1))})"
  defp text(nil), do: ""
  defp text(value), do: Number.to_s(value)

  defp string_time(value, context) do
    if Ruby.present?(value),
      do: ImportTime.parse(text(value), context.zone, clock(context.now), context.repo)
  end

  defp battery(nil), do: nil

  defp battery(value) do
    value = float(value)
    value = if value > 0 and value <= 1.0, do: value * 100, else: value
    if trunc(value) >= 0, do: trunc(value)
  end

  defp float(value) when is_number(value), do: value / 1
  defp float(value) when is_binary(value), do: Number.to_f(value)
  defp float(value), do: raise(ArgumentError, "undefined method 'to_f' for #{inspect(value)}")
  defp ruby_or(value, fallback), do: if(Ruby.truthy?(value), do: value, else: fallback)
  defp field(p, key), do: elem(field_key(p, key), 0)

  defp field_key({:object, pairs}, key) do
    Enum.find_value(pairs, {nil, nil}, fn {name, value} ->
      alias_key =
        Enum.find(
          @aliases[key],
          &(name in [&1, String.downcase(&1), String.upcase(&1), String.capitalize(&1)])
        )

      if alias_key, do: {value, alias_key}
    end)
  end

  defp index(nil, _), do: nil

  defp index({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
end
