defmodule Dawarich.Insights.Details.Totals do
  @moduledoc false
  alias Dawarich.Digests
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.StatsFormat

  def calculate(stats, unit) do
    toponyms = for s <- stats, is_list(s["toponyms"]), %{} = t <- s["toponyms"], do: t

    countries =
      for t <- toponyms,
          is_list(t["cities"]),
          t["cities"] != [],
          Ruby.present?(t["country"]),
          uniq: true,
          do: t["country"]

    cities =
      for t <- toponyms,
          is_list(t["cities"]),
          %{} = c <- t["cities"],
          Ruby.present?(c["city"]),
          uniq: true,
          do: c["city"]

    valid = Enum.filter(stats, &(Digests.to_i(&1["month"]) in 1..12))
    biggest = Enum.max_by(valid, & &1["distance"], &>=/2, fn -> nil end)

    %{
      distance: StatsFormat.rounded(Enum.sum(Enum.map(stats, &(&1["distance"] || 0))), unit),
      countries: length(countries),
      cities: length(cities),
      countries_list: Enum.sort(countries),
      days: Enum.sum(Enum.map(stats, &active_days/1)),
      biggest_month:
        if(biggest && biggest["distance"] > 0,
          do: %{
            year: biggest["year"],
            month: biggest["month"],
            distance: StatsFormat.rounded(biggest["distance"], unit)
          }
        )
    }
  end

  def comparison(current, previous, unit) do
    before = calculate(previous, unit)

    %{
      previous: before,
      distance_change: change(current.distance, before.distance),
      countries_change: current.countries - before.countries,
      cities_change: change(current.cities, before.cities),
      days_change: change(current.days, before.days)
    }
  end

  defp change(_current, 0), do: 0
  defp change(current, previous), do: round((current - previous) / previous * 100)

  defp active_days(%{"daily_distance" => daily}) when is_list(daily),
    do: Enum.count(daily, fn [_day, distance] -> Digests.to_i(distance) > 0 end)

  defp active_days(%{"daily_distance" => daily}) when is_map(daily),
    do: Enum.count(daily, fn {_day, distance} -> Digests.to_i(distance) > 0 end)
end
