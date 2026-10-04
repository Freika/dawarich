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
