defmodule Dawarich.Insights.MonthProjection do
  @moduledoc false
  alias Dawarich.{Repo, Digests, RubyInteger}

  def load(id, year, month) do
    case Repo.query!(
           "SELECT distance,monthly_distances,toponyms,first_time_visits,year_over_year FROM digests WHERE user_id=$1 AND year=$2 AND month=$3 AND period_type=0 LIMIT 1",
           [id, year, month],
           log: false
         ).rows do
      [[distance, daily, places, first, comparison]] ->
        places = Dawarich.Stats.Toponyms.sanitize(places)
        cities = for place <- places, city <- place["cities"], do: {place["country"], city}

        locations =
          cities
          |> Enum.sort_by(fn {_, city} -> -RubyInteger.to_i(city["stayed_for"]) end)
          |> Enum.take(3)

        codes = if locations != [], do: Dawarich.Insights.Details.CountryCodes.load(), else: []

        top_locations =
          for {country, city} <- locations do
            code =
              Dawarich.Insights.Details.CountryCodes.lookup(country, codes) ||
                if(country, do: country |> String.slice(0, 2) |> String.upcase(), else: "??")

            %{name: "#{city["city"]}, #{code}", minutes: RubyInteger.to_i(city["stayed_for"])}
          end

        %{
          "top_locations" => top_locations,
          "year" => year,
          "month" => month,
          "distance" => distance,
          "monthly_distances" => daily,
          "countries_count" => Digests.countries_count(places),
          "cities_count" => Digests.cities_count(places),
          "toponyms" =>
            for(
              {country, city} <- locations,
              do: %{"country" => country, "cities" => [Map.take(city, ~w(city stayed_for))]}
            ),
          "first_time_visits" => %{
            "countries" => names(first, "countries"),
            "cities" => names(first, "cities")
          },
          "year_over_year" => numbers(comparison, ~w(distance_change_percent countries_change))
        }

      _ ->
        nil
    end
  end

  defp names(map, key) when is_map(map),
    do: if(is_list(map[key]), do: map[key] |> Enum.filter(&is_binary/1) |> Enum.take(3), else: [])

  defp names(_, _), do: []

  defp numbers(map, keys) when is_map(map),
    do: Map.take(map, keys) |> Enum.filter(fn {_, value} -> is_number(value) end) |> Map.new()

  defp numbers(_, _), do: %{}
end
