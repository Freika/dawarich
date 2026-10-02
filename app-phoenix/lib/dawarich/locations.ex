defmodule Dawarich.Locations do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo, RubyFloat}

  @gap 1800
  @single 15
  @no_accuracy 999_999

  def rows(user_id, search) do
    {clauses, dates} = date_filters(search)

    Repo.query!(
      """
      WITH search_point AS (SELECT ST_SetSRID(ST_MakePoint($1::float8, $2::float8), 4326)::geography AS geom)
      SELECT COALESCE(p.timestamp, 0), ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry), p.city, p.country,
             p.altitude, p.accuracy, ST_Distance(p.lonlat, search_point.geom),
             #{RailsTime.sql("(to_timestamp(COALESCE(p.timestamp, 0)) AT TIME ZONE 'UTC')", 0)}
      FROM points p, search_point
      WHERE p.user_id = $3 AND ST_DWithin(p.lonlat, search_point.geom, $4::float8)#{Enum.join(clauses)}
      """,
      [search.lon, search.lat, user_id, search.radius * 1.0 | dates]
    ).rows
  end

  def term(search, rows) do
    points = rows |> Enum.map(&point/1) |> Enum.sort_by(& &1.ts)

    cond do
      tie?(points) -> {:replay, "matched points share a timestamp"}
      points == [] -> {:ok, result([])}
      true -> {:ok, result([location(search, visits(points))])}
    end
  end

  defp date_filters(search) do
    [{search.date_from, ">=", ""}, {search.date_to, "<", " + 1"}]
    |> Enum.reject(fn {date, _op, _shift} -> is_nil(date) end)
    |> Enum.with_index(5)
    |> Enum.map(fn {{date, op, shift}, n} ->
      {" AND p.timestamp #{op} extract(epoch FROM ($#{n}::date#{shift})::timestamptz)", date}
    end)
    |> Enum.unzip()
  end

  defp point([ts, lat, lon, city, country, altitude, accuracy, distance, date]) do
    %{
      ts: ts,
      coordinates: [lat, lon],
      city: city,
      country: country,
      altitude: altitude,
      accuracy: accuracy,
      distance: RubyFloat.round(distance, 2),
      date: date
    }
  end

  defp tie?(points),
    do: points |> Enum.chunk_every(2, 1, :discard) |> Enum.any?(fn [a, b] -> a.ts == b.ts end)

  defp visits(points) do
    points
    |> Enum.chunk_while([], &join/2, fn acc -> {:cont, Enum.reverse(acc), []} end)
    |> Enum.map(&visit/1)
    |> Enum.sort_by(& &1.ts, :desc)
  end

  defp join(%{ts: ts} = point, [%{ts: last} | _] = acc) when ts - last > @gap,
    do: {:cont, Enum.reverse(acc), [point]}

  defp join(point, acc), do: {:cont, [point | acc]}

  defp visit([first | _] = points) do
    last = List.last(points)
    count = length(points)
    minutes = if count > 1, do: RubyFloat.round((last.ts - first.ts) / 60), else: @single
    best = Enum.min_by(points, &(&1.accuracy || @no_accuracy))
    distance = RubyFloat.round(RubyFloat.sum(Enum.map(points, & &1.distance)) / count, 2)

    %{
      ts: first.ts,
      date: first.date,
      term:
        {:object,
         [
           {"timestamp", first.ts},
           {"date", first.date},
           {"coordinates", best.coordinates},
           {"distance_meters", distance},
           {"duration_estimate", duration(minutes)},
           {"points_count", count},
           {"accuracy_meters", best.accuracy},
           {"visit_details",
            {:object,
             [
               {"start_time", first.date},
               {"end_time", last.date},
               {"duration_minutes", minutes},
               {"city", best.city},
               {"country", best.country},
               {"altitude_range", altitudes(points)}
             ]}}
         ]}
    }
  end

  defp result(locations) do
    {:object,
     [
       {"query", nil},
       {"locations", locations},
       {"total_locations", length(locations)},
       {"search_metadata", {:object, []}}
     ]}
  end

  defp location(search, visits) do
    {:object,
     [
       {"place_name", search.name},
       {"coordinates", [search.lat, search.lon]},
       {"address", search.address},
       {"total_visits", length(visits)},
       {"first_visit", hd(visits).date},
       {"last_visit", List.last(visits).date},
       {"visits", visits |> Enum.take(search.limit) |> Enum.map(& &1.term)}
     ]}
  end

  defp duration(minutes) when minutes < 60, do: "~" <> plural(minutes, "minute")

  defp duration(minutes) do
    hours = "~" <> plural(div(minutes, 60), "hour")
    if rem(minutes, 60) == 0, do: hours, else: hours <> " " <> plural(rem(minutes, 60), "minute")
  end

  defp plural(1, word), do: "1 " <> word
  defp plural(count, word), do: "#{count} #{word}s"

  defp altitudes(points) do
    case for(%{altitude: altitude} when not is_nil(altitude) <- points, do: altitude) do
      [] ->
        nil

      values ->
        {low, high} = Enum.min_max(values)
        if low == high, do: "#{low}m", else: "#{low}m - #{high}m"
    end
  end
end
