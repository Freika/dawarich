defmodule Dawarich.Digests.Refresh.Aggregate do
  @moduledoc false
  alias Dawarich.Digests
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def year(stats) do
    monthly = for s <- stats, into: %{}, do: {to_string(s["month"]), to_string(s["distance"])}
    monthly = Enum.reduce(1..12, monthly, &Map.put_new(&2, to_string(&1), "0"))

    %{
      "distance" => distance(stats),
      "toponyms" => aggregate_toponyms(stats),
      "monthly_distances" => monthly
    }
  end

  def month(stat) do
    daily = stat["daily_distance"] || []

    daily =
      if is_map(daily), do: Map.to_list(daily), else: Enum.map(daily, fn [k, v] -> {k, v} end)

    %{
      "distance" => stat["distance"],
      "flight_distance" => stat["flight_distance"],
      "toponyms" => stat["toponyms"] || [],
      "monthly_distances" => Map.new(daily, fn {key, value} -> {to_string(key), value} end)
    }
  end

  def first(stats, year, month) do
    previous = Enum.filter(stats, &(period(&1) < {year, month || 0}))
    current = Enum.filter(stats, &(&1["year"] == year and (month == nil or &1["month"] == month)))

    %{
      "countries" => Enum.sort(countries(current, true) -- countries(previous, true)),
      "cities" => Enum.sort(cities(current) -- cities(previous))
    }
  end

  def comparison(stats, year, month) do
    {prev_year, prev_month} =
      case month do
        nil -> {year - 1, nil}
        1 -> {year - 1, 12}
        month -> {year, month - 1}
      end

    previous = Enum.filter(stats, &selected?(&1, prev_year, prev_month))
    current = Enum.filter(stats, &selected?(&1, year, month))
    previous = if month, do: Enum.take(previous, 1), else: previous
    current = if month, do: Enum.take(current, 1), else: current

    if previous == [] do
      %{}
    else
      result = %{
        "previous_year" => prev_year,
        "countries_change" => length(countries(current)) - length(countries(previous)),
        "cities_change" => length(cities(current)) - length(cities(previous))
      }

      result = if month, do: Map.put(result, "previous_month", prev_month), else: result
      before = distance(previous)

      if before == 0,
        do: result,
        else:
          Map.put(
            result,
            "distance_change_percent",
            round((distance(current) - before) / before * 100)
          )
    end
  end

  def all_time(all, scoped),
    do: %{
      "total_countries" => length(countries(all, true)),
      "total_cities" => length(cities(all)),
      "total_distance" => to_string(distance(scoped))
    }

  def city_minutes(stats) do
    stats
    |> Enum.flat_map(&toponyms/1)
    |> Enum.reduce(%{}, fn t, acc ->
      Enum.reduce(list(t["cities"]), acc, fn
        %{} = city, acc ->
          if Ruby.present?(city["city"]),
            do:
              Map.update(
                acc,
                city["city"],
                Digests.to_i(city["stayed_for"]),
                &(&1 + Digests.to_i(city["stayed_for"]))
              ),
            else: acc

        _, acc ->
          acc
      end)
    end)
  end

  def countries(stats, meaningful \\ false),
    do:
      for(
        t <- Enum.flat_map(stats, &toponyms/1),
        Ruby.present?(t["country"]),
        not meaningful or (is_list(t["cities"]) and t["cities"] != []),
        uniq: true,
        do: t["country"]
      )

  def cities(stats),
    do:
      for(
        t <- Enum.flat_map(stats, &toponyms/1),
        %{} = c <- list(t["cities"]),
        Ruby.present?(c["city"]),
        uniq: true,
        do: c["city"]
      )

  defp aggregate_toponyms(stats) do
    stats
    |> Enum.flat_map(&toponyms/1)
    |> Enum.reduce([], fn t, acc ->
      country = t["country"]

      if Ruby.present?(country) do
        names = for %{} = city <- list(t["cities"]), Ruby.present?(city["city"]), do: city["city"]

        cond do
          is_list(t["cities"]) and names == [] ->
            acc

          true ->
            case List.keyfind(acc, country, 0) do
              nil ->
                acc ++ [{country, Enum.uniq(names)}]

              {^country, before} ->
                List.keyreplace(acc, country, 0, {country, Enum.uniq(before ++ names)})
            end
        end
      else
        acc
      end
    end)
    |> Enum.sort_by(fn {_country, cities} -> -length(cities) end)
    |> Enum.map(fn {country, cities} ->
      %{"country" => country, "cities" => for(city <- Enum.sort(cities), do: %{"city" => city})}
    end)
  end

  defp selected?(stat, year, month),
    do: stat["year"] == year and (month == nil or stat["month"] == month)

  defp period(stat), do: {stat["year"], stat["month"]}
  defp distance(stats), do: Enum.sum(Enum.map(stats, &(&1["distance"] || 0)))
  defp toponyms(stat), do: Enum.filter(list(stat["toponyms"]), &is_map/1)
  defp list(value) when is_list(value), do: value
  defp list(_), do: []
end
