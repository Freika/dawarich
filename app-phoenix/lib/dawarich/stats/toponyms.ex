defmodule Dawarich.Stats.Toponyms do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def sanitize(raw) do
    for %{} = toponym <- if(is_list(raw), do: List.flatten(raw), else: []),
        is_nil(toponym["country"]) or is_binary(toponym["country"]),
        do: Map.put(toponym, "cities", sanitized_cities(toponym["cities"]))
  end

  def visited(toponyms),
    do: Enum.filter(toponyms, &(Ruby.present?(&1["country"]) and &1["cities"] != []))

  def known_countries(toponyms), do: Enum.count(toponyms, &(&1["country"] != nil))

  def countries(toponyms),
    do: toponyms |> visited() |> Enum.map(& &1["country"]) |> Enum.uniq() |> Enum.sort()

  def cities(toponyms),
    do: for(t <- toponyms, %{"city" => city} <- t["cities"], uniq: true, do: city) |> Enum.sort()

  defp sanitized_cities(list) when is_list(list),
    do: for(%{"city" => city} = entry <- list, is_binary(city) and Ruby.present?(city), do: entry)

  defp sanitized_cities(_other), do: []

  def year_places(stats, year, table) do
    toponyms = Enum.flat_map(stats, & &1.toponyms)

    countries =
      for t <- toponyms,
          t["cities"] != [] and Ruby.present?(t["country"]),
          uniq: true,
          do: Dawarich.CountryNames.normalize(t["country"], table)

    cities = for t <- toponyms, %{"city" => city} <- t["cities"], uniq: true, do: city

    grouped =
      toponyms
      |> Enum.reduce(%{}, fn t, acc ->
        case Dawarich.CountryNames.normalize(t["country"], table) do
          nil ->
            acc

          country ->
            Enum.reduce(t["cities"], acc, fn %{"city" => city}, a ->
              Map.update(a, country, [city], &[city | &1])
            end)
        end
      end)
      |> Enum.map(fn {country, names} -> {country, names |> Enum.uniq() |> Enum.sort()} end)
      |> Enum.sort()

    %{
      countries_count: length(countries),
      cities_count: length(cities),
      grouped: grouped,
      modal_id: "countries_cities_modal_#{year}"
    }
  end
end
