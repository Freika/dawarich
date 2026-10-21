defmodule Dawarich.Imports.OwntracksRec do
  @moduledoc false
  alias Dawarich.Imports.BoundedLines
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: RubyValue

  @connections %{"m" => "mobile", "w" => "wifi", "o" => "offline"}
  @triggers %{
    "p" => "background_event",
    "c" => "circular_region_event",
    "b" => "beacon_event",
    "r" => "report_location_message_event",
    "u" => "manual_event",
    "t" => "timer_based_event",
    "v" => "settings_monitoring_event"
  }

  def reduce(path, acc, fun) do
    path
    |> BoundedLines.stream()
    |> Enum.reduce(acc, fn line, acc ->
      case parse(line) do
        nil -> acc
        value -> fun.(value, acc)
      end
    end)
  end

  def params(p, context) do
    if p["_type"] != "waypoint" and Enum.all?(~w(lon lat tst), &Ruby.present?(p[&1])) do
      attrs = %{
        lonlat: "POINT(#{RubyValue.to_s(p["lon"])} #{RubyValue.to_s(p["lat"])})",
        timestamp: Ruby.to_i(p["tst"]),
        battery: p["batt"],
        ping: p["p"],
        altitude: p["alt"],
        accuracy: p["acc"],
        vertical_accuracy: p["vac"],
        velocity: speed(p),
        ssid: p["SSID"],
        bssid: p["BSSID"],
        tracker_id: p["tid"],
        inrids: p["inrids"],
        in_regions: p["inregions"],
        topic: p["topic"],
        battery_status: battery(p["bs"]),
        connection:
          if(is_nil(p["conn"]), do: "mobile", else: Map.get(@connections, p["conn"], "unknown")),
        trigger: Map.get(@triggers, p["t"], "unknown"),
        motion_data: motion(p)
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, p["alt"]), else: attrs
    end
  end

  defp parse(line) do
    line = line |> JsonStream.Scalar.scrub() |> String.trim_trailing("\n")

    parts =
      line
      |> String.split("\t")
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()

    parts = if length(parts) == 1, do: String.split(line, ~r/\s+/, parts: 3), else: parts

    case parts do
      [_, marker, json | _] -> if String.trim(marker) == "*", do: decode(json)
      _ -> nil
    end
  end

  defp decode(json) do
    JsonStream.reduce(
      {:bytes, json},
      nil,
      fn
        {:value, [], value, _, _}, _ -> materialize(value)
        _, acc -> acc
      end,
      &(&1 == []),
      mode: :compat
    )
  rescue
    JsonStream.Error -> nil
  end

  defp materialize({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, materialize(v)} end)
  defp materialize(list) when is_list(list), do: Enum.map(list, &materialize/1)
  defp materialize(value), do: value
  defp battery(nil), do: "unknown"

  defp battery(value),
    do: Map.get(%{1 => "unplugged", 2 => "charging", 3 => "full"}, Ruby.to_i(value), "unknown")

  defp motion(%{"m" => m} = p) when m not in [nil, false],
    do: if(Ruby.truthy?(p["_type"]), do: %{"m" => m, "_type" => p["_type"]}, else: %{"m" => m})

  defp motion(_), do: %{}

  defp speed(p) do
    if Ruby.present?(p["topic"]),
      do: (float(p["vel"]) * 1000 / 3600) |> Dawarich.RubyFloat.round(1) |> RubyValue.to_s(),
      else: p["vel"]
  end

  defp float(nil), do: 0.0
  defp float(value) when is_number(value), do: value / 1
  defp float(value) when is_binary(value), do: RubyValue.to_f(value)
  defp float(value), do: raise(ArgumentError, "undefined method 'to_f' for #{inspect(value)}")
end
