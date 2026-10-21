defmodule Dawarich.Jobs.PosixZone do
  @moduledoc false

  @source Path.expand("../../../priv/rails_time_zones.json", __DIR__)
  @external_resource @source
  @data @source |> File.read!() |> Jason.decode!()
  @names Map.keys(@data["zones"]) ++ Map.keys(@data["aliases"])
  @fixed ~r/\A([+-][0-1]?[0-9]):?([0-5][0-9])?\z/

  def resolve("CST5CDT"), do: "CST6CDT"

  def resolve(zone) do
    case fixed(zone) do
      nil -> Enum.find(prefixes(zone), &(&1 in @names))
      _ -> zone
    end
  end

  def load!(zone) do
    case fixed(zone) do
      nil -> raise ArgumentError, "invalid time zone"
      offset -> %{types: {{offset, false}}, offsets: [offset], transitions: {}}
    end
  end

  defp fixed(zone) do
    case Regex.run(@fixed, zone, capture: :all_but_first) do
      [hours | rest] ->
        hours = String.to_integer(hours)

        minutes =
          case rest do
            [value] -> String.to_integer(value)
            [] -> 0
          end

        if abs(hours) <= 11, do: hours * 3600 + minutes * 60 * if(hours < 0, do: -1, else: 1)

      _ ->
        nil
    end
  end

  defp prefixes(zone) do
    for length <- String.length(zone)..1//-1, do: String.slice(zone, 0, length)
  end
end
