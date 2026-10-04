defmodule Dawarich.Trips.PlanGeojson do
  @moduledoc false

  def build(plan) do
    features =
      Enum.flat_map(Enum.with_index(plan.days), fn {day, day_index} ->
        stops =
          for {stop, stop_index} <- Enum.with_index(day.stops),
              located?(stop),
              do:
                point(stop, %{
                  "kind" => "stop",
                  "name" => stop.name,
                  "day" => day_index,
                  "number" => stop_index + 1
                })

        stops ++ route(stops, day_index)
      end) ++ places(plan.accommodations, "stay") ++ places(plan.unplanned_places, "unplanned")

    if features != [], do: %{"type" => "FeatureCollection", "features" => features}
  end

  def encode(nil), do: nil

  def encode(geojson),
    do:
      geojson
      |> ordered()
      |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
      |> IO.iodata_to_binary()

  defp ordered(value) when is_map(value) do
    keys =
      cond do
        value["type"] == "FeatureCollection" -> ~w(type features)
        value["type"] == "Feature" -> ~w(type geometry properties)
        value["type"] in ["Point", "LineString"] -> ~w(type coordinates)
        true -> ~w(kind name day number)
      end

    {:object, for(key <- keys, Map.has_key?(value, key), do: {key, ordered(value[key])})}
  end

  defp ordered(value) when is_list(value), do: Enum.map(value, &ordered/1)
  defp ordered(value), do: value

  defp places(places, kind) do
    for place <- places,
        located?(place),
        do: point(place, %{"kind" => kind, "name" => place.name})
  end

  defp located?(record), do: not is_nil(record.latitude) and not is_nil(record.longitude)

  defp point(record, properties),
    do: %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "Point",
        "coordinates" => [number(record.longitude), number(record.latitude)]
      },
      "properties" => properties
    }

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value), do: value * 1.0

  defp route(stops, day) when length(stops) >= 2,
    do: [
      %{
        "type" => "Feature",
        "geometry" => %{
          "type" => "LineString",
          "coordinates" => Enum.map(stops, & &1["geometry"]["coordinates"])
        },
        "properties" => %{"kind" => "route", "day" => day}
      }
    ]

  defp route(_stops, _day), do: []
end
