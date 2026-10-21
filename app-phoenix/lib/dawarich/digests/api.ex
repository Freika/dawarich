defmodule Dawarich.Digests.Api do
  @moduledoc false

  alias Dawarich.{Digests, Distance, I18n, Jsonb, RailsTime, Repo, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Stats.Insights

  @months ~w(january february march april may june july august september october november december)

  def index(user_id, now) do
    [[today]] = Repo.query!("SELECT ($1::timestamptz)::date", [now]).rows

    rows =
      Repo.query!(
        "SELECT year, distance, toponyms, #{RailsTime.sql("created_at", 0)} FROM digests " <>
          "WHERE user_id = $1 AND period_type = 1 AND year < $2 ORDER BY year DESC",
        [user_id, today.year]
      ).rows

    with {:ok, digests} <- list(rows) do
      years = Digests.available_years(user_id, %{today: today, cutoff: nil})
      {:ok, {:object, [{"digests", digests}, {"availableYears", years}]}}
    end
  end

  def show(user_id, year) do
    case Repo.query!(
           """
           SELECT year, distance, toponyms, monthly_distances::text, time_spent_by_location::text, first_time_visits::text,
                  year_over_year::text, all_time_stats::text, travel_patterns::text,
                  #{RailsTime.sql("created_at", 0)}, #{RailsTime.sql("updated_at", 0)}, updated_at
           FROM digests WHERE user_id = $1 AND period_type = 1 AND year = $2 LIMIT 1
           """,
           [user_id, year]
         ).rows do
      [] ->
        :not_found

      [
        [
          year,
          distance,
          toponyms,
          monthly,
          spent,
          first,
          yoy,
          all_time,
          patterns,
          created,
          updated,
          modified
        ]
      ] ->
        {:ok,
         %{
           year: year,
           distance: distance,
           toponyms: toponyms,
           monthly: Jsonb.decode(monthly),
           spent: Jsonb.decode(spent),
           first: Jsonb.decode(first),
           yoy: Jsonb.decode(yoy),
           all_time: Jsonb.decode(all_time),
           patterns: Jsonb.decode(patterns),
           created_at: created,
           updated_at: updated,
           modified: modified
         }}
    end
  end

  def detail(digest, unit) do
    with {:ok, countries} <- countries(digest.toponyms),
         {:ok, country_count, city_count} <- counts(digest.toponyms),
         {:ok, months} <- months(digest.monthly),
         {:ok, yoy} <- yoy(digest.yoy),
         {:ok, all_time} <- all_time(digest.all_time),
         {:ok, patterns} <- Insights.patterns(digest.patterns) do
      {:ok,
       {:object,
        [
          {"year", digest.year},
          {"distance",
           {:object,
            [
              {"meters", digest.distance},
              {"converted", round(Distance.convert(digest.distance, unit))},
              {"unit", unit},
              {"comparisonText", comparison_text(digest.distance)}
            ]}},
          {"toponyms",
           {:object,
            [
              {"countriesCount", country_count},
              {"citiesCount", city_count},
              {"countries", countries}
            ]}},
          {"monthlyDistances", months},
          {"timeSpentByLocation", digest.spent},
          {"firstTimeVisits", digest.first},
          {"yearOverYear", yoy},
          {"allTimeStats", all_time},
          {"travelPatterns",
           {:object,
            [
              {"timeOfDay", Insights.pattern(patterns, "time_of_day")},
              {"seasonality", Insights.pattern(patterns, "seasonality")},
              {"activityBreakdown", Insights.pattern(patterns, "activity_breakdown")}
            ]}},
          {"createdAt", digest.created_at},
          {"updatedAt", digest.updated_at}
        ]}}
    end
  end

  defp list(rows) do
    rows
    |> Enum.reduce_while({:ok, []}, fn [year, distance, toponyms, created], {:ok, acc} ->
      case counts(toponyms) do
        {:ok, countries, cities} ->
          digest =
            {:object,
             [
               {"year", year},
               {"distance", distance},
               {"countriesCount", countries},
               {"citiesCount", cities},
               {"createdAt", created}
             ]}

          {:cont, {:ok, [digest | acc]}}

        replay ->
          {:halt, replay}
      end
    end)
    |> case do
      {:ok, digests} -> {:ok, Enum.reverse(digests)}
      replay -> replay
    end
  end

  defp counts(list) when is_list(list) do
    if Enum.all?(list, &toponym?/1),
      do: {:ok, Digests.countries_count(list), Digests.cities_count(list)},
      else: {:replay, "digest toponyms element"}
  end

  defp counts(_other), do: {:ok, 0, 0}

  defp countries(nil), do: {:ok, []}
  defp countries(false), do: {:ok, []}
  defp countries(map) when map == %{}, do: {:ok, []}

  defp countries(list) when is_list(list) do
    if Enum.all?(list, &toponym?/1),
      do:
        {:ok,
         for toponym <- list, Ruby.present?(toponym["country"]) do
           cities = for city <- toponym["cities"] || [], city["city"] != nil, do: city["city"]
           {:object, [{"country", toponym["country"]}, {"cities", cities}]}
         end},
      else: {:replay, "digest toponyms element"}
  end

  defp countries(_other), do: {:replay, "digest toponyms that are not an array"}

  defp toponym?(%{} = toponym) do
    (is_nil(toponym["country"]) or is_binary(toponym["country"])) and
      (is_nil(toponym["cities"]) or
         (is_list(toponym["cities"]) and Enum.all?(toponym["cities"], &city?/1)))
  end

  defp toponym?(_other), do: false

  defp city?(%{} = city), do: not (is_map(city["city"]) or is_list(city["city"]))
  defp city?(_other), do: false

  defp months(value) when value in [nil, false], do: months({:object, []})

  defp months({:object, _} = raw) do
    @months
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {name, month}, {:ok, acc} ->
      case to_f(Jsonb.get(raw, Integer.to_string(month))) do
        {:ok, meters} -> {:cont, {:ok, [{name, meters} | acc]}}
        :error -> {:halt, {:replay, "monthly distance for month #{month}"}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, {:object, Enum.reverse(pairs)}}
      replay -> replay
    end
  end

  defp months(_other), do: {:replay, "monthly_distances that is not an object"}

  defp to_f(nil), do: {:ok, 0.0}
  defp to_f(value) when is_integer(value), do: {:ok, value * 1.0}
  defp to_f(value) when is_float(value), do: {:ok, value}
  defp to_f(value) when is_binary(value), do: {:ok, Ruby.to_f(value)}
  defp to_f(_value), do: :error

  defp yoy(value) do
    cond do
      Ruby.blank?(value) ->
        {:ok, nil}

      match?({:object, _}, value) ->
        {:ok,
         {:object,
          [
            {"distanceChangePercent", Jsonb.get(value, "distance_change_percent")},
            {"countriesChange", Jsonb.get(value, "countries_change")},
            {"citiesChange", Jsonb.get(value, "cities_change")}
          ]}}

      true ->
        {:replay, "year_over_year shape"}
    end
  end

  defp all_time(value) when value in [nil, false], do: all_time({:object, []})

  defp all_time({:object, _} = stats) do
    case Jsonb.get(stats, "total_distance") || 0 do
      distance when is_binary(distance) or is_number(distance) or is_boolean(distance) ->
        {:ok,
         {:object,
          [
            {"totalCountries", Jsonb.get(stats, "total_countries") || 0},
            {"totalCities", Jsonb.get(stats, "total_cities") || 0},
            {"totalDistance", Ruby.to_s(distance)}
          ]}}

      _ ->
        {:replay, "all_time_stats total_distance shape"}
    end
  end

  defp all_time(_other), do: {:replay, "all_time_stats shape"}

  defp comparison_text(distance) do
    km = distance / 1000

    {key, base} =
      if km >= 384_400, do: {"moon_distance", 384_400}, else: {"earth_circumference", 40_075}

    percentage = Ruby.to_s(RubyFloat.round(km / base * 100, 1))
    {:ok, text} = I18n.t("en", "helpers.users.digests." <> key, %{"percentage" => percentage})
    text
  end
end
