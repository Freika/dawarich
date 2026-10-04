defmodule Dawarich.Digests.Comparison do
  @moduledoc false

  alias Dawarich.Digests.Toponyms

  def monthly(history, year, month) do
    previous = if month == 1, do: {year - 1, 12}, else: {year, month - 1}
    result = compare(history, {year, month}, previous)
    if result == %{}, do: result, else: Map.put(result, "previous_month", elem(previous, 1))
  end

  def yearly(history, year), do: compare(history, {year, nil}, {year - 1, nil})

  def all_time(history, distance) do
    %{
      "total_countries" => length(Toponyms.countries(history)),
      "total_cities" => length(Toponyms.cities(history)),
      "total_distance" => distance
    }
  end

  defp compare(history, current, previous) do
    before = select(history, previous)

    if before == [] do
      %{}
    else
      current = select(history, current)

      result = %{
        "previous_year" => elem(previous, 0),
        "countries_change" =>
          length(Toponyms.countries(current, false)) - length(Toponyms.countries(before, false)),
        "cities_change" => length(Toponyms.cities(current)) - length(Toponyms.cities(before))
      }

      previous_distance = distance(before)

      if previous_distance == 0 do
        result
      else
        Map.put(
          result,
          "distance_change_percent",
          round((distance(current) - previous_distance) / previous_distance * 100)
        )
      end
    end
  end

  defp select(history, {year, month}),
    do: Enum.filter(history, &(&1["year"] == year and (is_nil(month) or &1["month"] == month)))

  defp distance(stats), do: Enum.sum(Enum.map(stats, &(&1["distance"] || 0)))
end
