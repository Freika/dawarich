defmodule Dawarich.Stats.ToponymRuns do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @bridge 7 * 24 * 60 * 60

  def new(names, min_minutes),
    do: %{names: names, min: min_minutes, countries: [], flight: 0, run: nil}

  def add([_id, timestamp, city, country_name, country_id, velocity], acc) do
    if flyover?(velocity) do
      acc = %{acc | flight: acc.flight + 1}
      if acc.flight == 2, do: finish(acc), else: acc
    else
      acc = %{acc | flight: 0}

      if is_nil(country_name) or is_nil(city),
        do: acc,
        else: extend(acc, timestamp, city, Map.get(acc.names, country_id) || country_name)
    end
  end

  def result(acc) do
    %{countries: countries, min: min} = finish(acc)

    for {country, cities} <- countries do
      %{
        "country" => country,
        "cities" =>
          for {city, totals} <- cities, div(totals.seconds, 60) >= min do
            %{
              "city" => city,
              "points" => totals.points,
              "timestamp" => totals.timestamp,
              "stayed_for" => div(totals.seconds, 60)
            }
          end
      }
    end
  end

  defp flyover?(nil), do: false
  defp flyover?(velocity), do: Ruby.to_f(velocity) * 3.6 > 500

  defp extend(%{run: run} = acc, timestamp, city, country) do
    acc =
      if run && (run.country != country or run.city != city or timestamp - run.last > @bridge),
        do: finish(acc),
        else: acc

    run = acc.run || %{country: country, city: city, first: timestamp, last: timestamp, points: 0}
    %{acc | run: %{run | last: timestamp, points: run.points + 1}}
  end

  defp finish(%{run: nil} = acc), do: acc

  defp finish(%{run: run, countries: countries} = acc) do
    cities = keyget(countries, run.country, [])
    totals = keyget(cities, run.city, %{seconds: 0, points: 0, timestamp: 0})

    totals = %{
      seconds: totals.seconds + run.last - run.first,
      points: totals.points + run.points,
      timestamp: run.last
    }

    cities = List.keystore(cities, run.city, 0, {run.city, totals})
    %{acc | run: nil, countries: List.keystore(countries, run.country, 0, {run.country, cities})}
  end

  defp keyget(list, key, default) do
    case List.keyfind(list, key, 0) do
      {^key, value} -> value
      nil -> default
    end
  end
end
