defmodule Dawarich.Digests do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{Repo, Stats}

  @yearly 1

  def to_i(value) when is_integer(value), do: value
  def to_i(value) when is_float(value), do: trunc(value)
  def to_i(value) when is_binary(value), do: DawarichWeb.Params.ruby_to_i(value)
  def to_i(_value), do: 0

  def index(user_id, context) do
    digests =
      Repo.query!(
        """
        SELECT year, distance, toponyms, first_time_visits, sharing_settings
        FROM digests WHERE user_id = $1 AND period_type = $2 AND year < $3 ORDER BY year DESC
        """,
        [user_id, @yearly, context.today.year]
      ).rows
      |> Enum.map(fn [year, distance, toponyms, first, sharing] ->
        %{
          year: year,
          distance: distance,
          toponyms: toponyms(toponyms),
          first_time_countries: list(map(first)["countries"]),
          first_time_cities: list(map(first)["cities"]),
          sharing_enabled: map(sharing)["enabled"] == true
        }
      end)

    %{digests: digests, available_years: available_years(user_id, context)}
  end

  def get(user_id, year) do
    case Repo.query!(
           """
           SELECT year, distance, toponyms, first_time_visits, time_spent_by_location, year_over_year,
                  all_time_stats, monthly_distances, sharing_settings, sharing_uuid::text
           FROM digests WHERE user_id = $1 AND period_type = $2 AND year = $3 LIMIT 1
           """,
           [user_id, @yearly, year]
         ).rows do
      [] -> nil
      [row] -> digest(row)
    end
  end

  def countries_count(toponyms), do: Enum.count(toponyms, &Ruby.present?(&1["country"]))

  def cities_count(toponyms), do: toponyms |> Enum.map(&length(list(&1["cities"]))) |> Enum.sum()

  defp digest([year, distance, toponyms, first, spent, yoy, all_time, monthly, sharing, uuid]) do
    {first, spent, yoy, all_time, sharing} =
      {map(first), map(spent), map(yoy), map(all_time), map(sharing)}

    countries = for %{} = country <- list(spent["countries"]), do: country

    %{
      year: year,
      distance: distance,
      toponyms: toponyms(toponyms),
      first_time_countries: list(first["countries"]),
      first_time_cities: list(first["cities"]),
      top_countries: countries,
      total_minutes: minutes(spent["total_country_minutes"], countries),
      yoy_distance_change:
        if(is_number(yoy["distance_change_percent"]), do: yoy["distance_change_percent"]),
      previous_year: yoy["previous_year"],
      total_countries_all_time: all_time["total_countries"] || 0,
      total_cities_all_time: all_time["total_cities"] || 0,
      total_distance_all_time: to_i(all_time["total_distance"] || 0),
      monthly_distances: monthly(monthly),
      sharing_enabled: sharing["enabled"] == true,
      sharing_expiration: sharing["expiration"],
      sharing_uuid: uuid
    }
  end

  defp available_years(user_id, context) do
    tracked =
      for [year, month] <-
            Repo.query!("SELECT DISTINCT year, month FROM stats WHERE user_id = $1", [user_id]).rows,
          Stats.in_window?(%{year: year, month: month}, context.cutoff),
          uniq: true,
          do: year

    existing =
      for [year] <-
            Repo.query!("SELECT year FROM digests WHERE user_id = $1 AND period_type = $2", [
              user_id,
              @yearly
            ]).rows,
          do: year

    ((tracked -- existing) -- [context.today.year]) |> Enum.sort(:desc)
  end

  defp minutes(total, _countries) when is_number(total), do: total
  defp minutes(_total, countries), do: countries |> Enum.map(&to_i(&1["minutes"])) |> Enum.sum()

  defp monthly(%{} = map), do: Enum.sort_by(map, fn {month, _} -> to_i(month) end)

  defp monthly(list) when is_list(list),
    do:
      list
      |> Enum.flat_map(fn
        [month, meters] -> [{month, meters}]
        _ -> []
      end)
      |> Enum.sort_by(fn {month, _} -> to_i(month) end)

  defp monthly(_other), do: []

  defp toponyms(list) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp toponyms(_other), do: []

  defp map(%{} = value), do: value
  defp map(_value), do: %{}

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []
end
