defmodule Dawarich.Digests.Refresh.TimeSpent do
  @moduledoc false
  alias Dawarich.Digests
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def fetch(repo, user_id, first, last, zone) do
    rows =
      repo.query!(
        """
        SELECT DATE(to_timestamp(timestamp) AT TIME ZONE $4), country_name, MIN(timestamp), MAX(timestamp)
        FROM points WHERE user_id=$1 AND timestamp >= $2 AND timestamp <= $3
          AND country_name IS NOT NULL AND country_name != ''
        GROUP BY 1,country_name ORDER BY 1,MIN(timestamp)
        """,
        [user_id, first, last, zone]
      ).rows

    countries(rows)
  end

  def countries(rows) do
    rows
    |> Enum.chunk_by(&hd/1)
    |> Enum.reduce([], fn day, acc ->
      case day do
        [[_date, country, _first, _last]] ->
          add(acc, country, 1440)

        rows ->
          spans = for [_date, country, first, last] <- rows, do: {country, max(last - first, 60)}
          total = spans |> Enum.map(&elem(&1, 1)) |> Enum.sum()

          Enum.reduce(spans, acc, fn {country, span}, result ->
            add(result, country, round(span / total * 1440))
          end)
      end
    end)
  end

  def compose(countries, stats) do
    cities =
      for stat <- stats,
          %{} = t <- list(stat["toponyms"]),
          %{} = city <- list(t["cities"]),
          Ruby.present?(city["city"]),
          do: {city["city"], Digests.to_i(city["stayed_for"])}

    cities = Enum.reduce(cities, [], fn {name, minutes}, result -> add(result, name, minutes) end)

    %{
      "countries" => top(countries),
      "cities" => top(cities),
      "total_country_minutes" => countries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    }
  end

  defp top(rows),
    do:
      rows
      |> Enum.sort_by(&(-elem(&1, 1)))
      |> Enum.take(10)
      |> Enum.map(fn {name, minutes} -> %{"name" => name, "minutes" => minutes} end)

  defp add(rows, key, n) do
    case List.keyfind(rows, key, 0) do
      nil -> rows ++ [{key, n}]
      {^key, before} -> List.keyreplace(rows, key, 0, {key, before + n})
    end
  end

  defp list(value) when is_list(value), do: value
  defp list(_), do: []
end
