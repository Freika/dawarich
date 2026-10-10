defmodule Dawarich.Digests.Pages do
  @moduledoc false
  alias Dawarich.Analytics.Period
  alias Dawarich.{Digests, Repo}

  def index(scope, params \\ %{}, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(scope, params, :digest, opts) do
      rows =
        Repo.query!(
          "SELECT year,distance,toponyms,first_time_visits,sharing_settings->>'enabled' FROM digests WHERE user_id=$1 AND period_type=1 AND year<$2 ORDER BY year DESC LIMIT 51 OFFSET $3",
          [scope.user.id, period.today.year, (period.page - 1) * 50],
          log: false
        ).rows

      digests =
        Enum.take(rows, 50)
        |> Enum.map(fn [year, distance, toponyms, first, enabled] ->
          card(year, distance, toponyms, first, enabled)
        end)

      available = Digests.available_years(scope.user.id, period)

      {:ok,
       %{
         digests: digests,
         available_years: Enum.slice(available, (period.page - 1) * 50, 50),
         page: period.page,
         more: length(rows) > 50 or length(available) > period.page * 50,
         restricted: period.restricted,
         unit: period.unit,
         period: period,
         active: Dawarich.Digests.Commands.active?(scope.user, period.now)
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def get(scope, params, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(scope, params, :digest, opts) do
      columns =
        if period.restricted,
          do: "year,distance,toponyms,first_time_visits,sharing_settings->>'enabled'",
          else:
            "year,distance,toponyms,first_time_visits,sharing_settings->>'enabled',time_spent_by_location,year_over_year,all_time_stats,monthly_distances,sharing_settings->>'expiration'"

      case Repo.query!(
             "SELECT #{columns} FROM digests WHERE user_id=$1 AND period_type=1 AND year=$2 LIMIT 1",
             [scope.user.id, period.year],
             log: false
           ).rows do
        [] ->
          {:error, :not_found}

        [[year, distance, toponyms, first, enabled | rest]] ->
          data =
            summary(year, distance, toponyms, first, enabled)
            |> Map.merge(%{restricted: period.restricted, unit: period.unit, period: period})

          if period.restricted, do: {:ok, data}, else: full(data, rest)
      end
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  defp card(year, distance, toponyms, first, enabled) do
    data = summary(year, distance, toponyms, first, enabled)

    %{
      year: year,
      distance: distance,
      sharing_enabled: data.sharing_enabled,
      countries_count: Digests.countries_count(data.toponyms),
      cities_count: Digests.cities_count(data.toponyms),
      first_time_countries_count: length(data.first_time_countries),
      first_time_cities_count: length(data.first_time_cities)
    }
  end

  defp summary(year, distance, toponyms, first, enabled) do
    %{
      year: year,
      distance: distance,
      toponyms: Period.narrow(toponyms),
      first_time_countries: values(first, "countries"),
      first_time_cities: values(first, "cities"),
      sharing_enabled: enabled == "true"
    }
  end

  defp full(data, [spent, yoy, all_time, monthly, expiry]) do
    countries =
      for %{"name" => name, "minutes" => minutes} <- values(spent, "countries"),
          is_binary(name) and is_number(minutes),
          do: %{"name" => name, "minutes" => minutes}

    monthly =
      case monthly do
        %{} -> Map.to_list(monthly)
        rows when is_list(rows) -> for [month, meters] <- rows, do: {month, meters}
        _ -> []
      end

    if length(monthly) <= 12 and
         Enum.all?(monthly, fn {month, meters} ->
           Digests.to_i(month) in 1..12 and is_number(meters)
         end) do
      {:ok,
       Map.merge(data, %{
         top_countries: countries,
         total_minutes:
           scalar(spent, "total_country_minutes", Enum.sum(Enum.map(countries, & &1["minutes"]))),
         yoy_distance_change: scalar(yoy, "distance_change_percent", nil),
         previous_year: scalar(yoy, "previous_year", nil),
         total_countries_all_time: scalar(all_time, "total_countries", 0),
         total_cities_all_time: scalar(all_time, "total_cities", 0),
         total_distance_all_time: integer(all_time, "total_distance"),
         monthly_distances: Enum.sort_by(monthly, fn {month, _} -> Digests.to_i(month) end),
         sharing_expiration: expiry
       })}
    else
      {:error, :invalid_input}
    end
  end

  defp values(map, key) when is_map(map),
    do:
      if(is_list(map[key]),
        do:
          Enum.flat_map(map[key], fn
            value when is_binary(value) -> [value]
            value when is_map(value) -> [Map.take(value, ~w(city country name minutes))]
            _ -> []
          end),
        else: []
      )

  defp values(_, _), do: []

  defp integer(map, key) when is_map(map), do: Digests.to_i(map[key] || 0)
  defp integer(_, _), do: 0

  defp scalar(map, key, default) when is_map(map),
    do: if(is_number(map[key]), do: map[key], else: default)

  defp scalar(_, _, default), do: default
end
