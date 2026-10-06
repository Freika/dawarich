defmodule Dawarich.Locations.Closure do
  @moduledoc false

  alias Dawarich.{RailsTime, RubyFloat}

  @gap 1800
  @single 15
  @no_accuracy 999_999

  def read(user, params) do
    cond do
      not Dawarich.Ingest.Ruby.present?(params["lat"]) or
          not Dawarich.Ingest.Ruby.present?(params["lon"]) ->
        error(400, "coordinates_lat_lon_are_required")

      true ->
        lat = Dawarich.Ingest.Ruby.to_f(params["lat"])
        lon = Dawarich.Ingest.Ruby.to_f(params["lon"])

        if abs(lat) > 90 or abs(lon) > 180 do
          error(400, "invalid_coordinates_lat_must_be_90_90_lon_must_be")
        else
          search = %{
            lat: lat,
            lon: lon,
            limit: count(params["limit"], 50),
            radius: count(params["radius_override"], 500),
            date_from: date(params["date_from"]),
            date_to: date(params["date_to"]),
            name: params["name"],
            address: params["address"]
          }

          case RailsTime.with_zone(user.timezone, fn ->
                 term(search, Dawarich.Locations.rows(user.id, search))
               end) do
            {:ok, body} -> {:ok, 200, body}
            _ -> error(500, "search_failed_please_try_again")
          end
        end
    end
  rescue
    _ -> error(500, "search_failed_please_try_again")
  end

  defp count(nil, default), do: default
  defp count(value, _), do: Dawarich.Ingest.Ruby.to_i(value)

  defp date(value) do
    parts = Dawarich.Imports.DateParts.parse(value || "")

    with year when is_integer(year) <- parts["year"],
         month when is_integer(month) <- parts["mon"],
         day when is_integer(day) <- parts["mday"],
         {:ok, date} <- Date.new(year, month, day),
         do: date,
         else: (_ -> nil)
  rescue
    _ -> nil
  end

  defp error(status, key),
    do: {:ok, status, %{"error" => Dawarich.I18n.en!("controllers.api.v1.locations." <> key)}}

  def term(search, rows) do
    if search.limit < 0, do: raise(ArgumentError)
    points = rows |> Enum.map(&point/1) |> Enum.sort_by(& &1.ts)

    cond do
      points == [] -> {:ok, result([])}
      true -> {:ok, result([location(search, visits(points))])}
    end
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
