defmodule Dawarich.CountriesAndCities do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @bridge 7 * 24 * 60 * 60

  @points """
  SELECT id, timestamp, city, country_name, country_id, velocity FROM points
  WHERE user_id = $1 AND (anomaly = false OR anomaly IS NULL) AND timestamp BETWEEN $2::bigint AND $3::bigint
  ORDER BY timestamp, id
  """

  def range(start_value, end_value, now) do
    [[low, high]] =
      Repo.query!(
        "SELECT extract(epoch FROM make_timestamptz(1970, 1, 1, 0, 0, 0))::bigint, " <>
          "extract(epoch FROM make_timestamptz(2100, 1, 1, 0, 0, 0))::bigint"
      ).rows

    {resolve(start_value, low, high, now), resolve(end_value, low, high, now)}
  end

  def term(user_id, {start_at, end_at}, min_minutes) do
    points =
      for [id, timestamp, city, country, country_id, velocity] <-
            Repo.query!(@points, [user_id, start_at, end_at]).rows,
          do: %{
            id: id,
            timestamp: timestamp,
            city: city,
            country_name: country,
            country_id: country_id,
            velocity: velocity
          }

    names = country_names(points)

    data =
      points
      |> segments()
      |> Enum.flat_map(&runs(&1, names))
      |> group(& &1.country)
      |> Enum.map(fn {country, runs} ->
        {:object, [{"country", country}, {"cities", cities(runs, min_minutes)}]}
      end)

    {:object, [{"data", data}]}
  end

  defp resolve({:epoch, value}, low, high, _now), do: value |> max(low) |> min(high)

  defp resolve({:text, text}, low, high, now) do
    [[epoch, year]] =
      Repo.query!(
        "SELECT floor(extract(epoch FROM $1::text::timestamptz))::bigint, extract(year FROM $1::text::timestamptz)::int",
        [text]
      ).rows

    if year == 2000 and not String.contains?(text, "2000"),
      do: DateTime.to_unix(now),
      else: epoch |> max(low) |> min(high)
  end

  defp country_names(points) do
    case points |> Enum.map(& &1.country_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        Map.new(Repo.query!("SELECT id, name FROM countries WHERE id = ANY($1)", [ids]).rows, fn [
                                                                                                   id,
                                                                                                   name
                                                                                                 ] ->
          {id, name}
        end)
    end
  end

  defp segments(points) do
    points
    |> Enum.chunk_by(&flyover?/1)
    |> Enum.reduce([[]], fn [point | _] = chunk, [current | done] ->
      cond do
        not flyover?(point) -> [Enum.reverse(chunk, current) | done]
        length(chunk) >= 2 -> [[], current | done]
        true -> [current | done]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  defp flyover?(%{velocity: nil}), do: false
  defp flyover?(%{velocity: velocity}), do: Ruby.to_f(velocity) * 3.6 > 500

  defp runs(segment, names) do
    segment
    |> Enum.reject(&(is_nil(&1.country_name) or is_nil(&1.city)))
    |> Enum.reduce([], fn point, acc ->
      case acc do
        [[previous | _] = run | rest] ->
          if separate?(previous, point, names),
            do: [[point], run | rest],
            else: [[point | run] | rest]

        [] ->
          [[point]]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&run(Enum.reverse(&1), names))
  end

  defp separate?(previous, current, names),
    do:
      previous.city != current.city or canonical(previous, names) != canonical(current, names) or
        current.timestamp - previous.timestamp > @bridge

  defp run([first | _] = points, names) do
    stamps = Enum.map(points, & &1.timestamp)

    %{
      country: canonical(first, names),
      city: first.city,
      points: length(points),
      last: Enum.max(stamps),
      duration: Enum.max(stamps) - Enum.min(stamps)
    }
  end

  defp canonical(%{country_id: nil, country_name: name}, _names), do: name
  defp canonical(%{country_id: id, country_name: name}, names), do: Map.get(names, id) || name

  defp cities(runs, min_minutes) do
    runs
    |> group(& &1.city)
    |> Enum.flat_map(fn {city, city_runs} ->
      minutes = div(city_runs |> Enum.map(& &1.duration) |> Enum.sum(), 60)

      if minutes < min_minutes,
        do: [],
        else: [
          {:object,
           [
             {"city", city},
             {"points", city_runs |> Enum.map(& &1.points) |> Enum.sum()},
             {"timestamp", city_runs |> Enum.map(& &1.last) |> Enum.max()},
             {"stayed_for", minutes}
           ]}
        ]
    end)
  end

  defp group(items, key) do
    {keys, groups} =
      Enum.reduce(items, {[], %{}}, fn item, {keys, groups} ->
        k = key.(item)

        {if(Map.has_key?(groups, k), do: keys, else: [k | keys]),
         Map.update(groups, k, [item], &[item | &1])}
      end)

    keys |> Enum.reverse() |> Enum.map(&{&1, Enum.reverse(groups[&1])})
  end
end
