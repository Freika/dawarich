defmodule Dawarich.Digests.PageWindow do
  @moduledoc false
  alias Dawarich.Digests

  def prepare(data) do
    page = data.period.page
    top = data.toponyms
    countries = data.first_time_countries
    cities = data.first_time_cities
    max_cities = Enum.map(top, &length(&1["cities"])) |> Enum.max(fn -> 0 end)

    Map.merge(data, %{
      countries_count: Digests.countries_count(top),
      cities_count: Digests.cities_count(top),
      first_time_countries_count: length(countries),
      first_time_cities_count: length(cities),
      first_time_countries: Enum.slice(countries, (page - 1) * 50, 50),
      first_time_cities: Enum.take(cities, 10),
      toponyms:
        top
        |> Enum.slice((page - 1) * 50, 50)
        |> Enum.map(fn row ->
          %{"country" => row["country"], "city_count" => length(row["cities"]), "cities" => []}
        end),
      max_city_count: max_cities,
      places_more: max(length(top), length(countries)) > page * 50
    })
    |> narrow_countries()
  end

  defp narrow_countries(%{top_countries: countries} = data),
    do: %{data | top_countries: Enum.take(countries, 5)}

  defp narrow_countries(data), do: data
end
