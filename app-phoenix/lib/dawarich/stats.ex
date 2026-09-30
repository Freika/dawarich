defmodule Dawarich.Stats do
  @moduledoc false

  alias Dawarich.{Entitlements, LocalTime, Repo, RubyFloat}
  alias Dawarich.Stats.{PointCounts, Toponyms}

  def context(user, now, self_hosted) do
    {zone, today} = LocalTime.local(user.settings, now)
    restricted = not Entitlements.full_access?(user, self_hosted, now)

    %{
      zone: zone,
      today: today,
      restricted: restricted,
      cutoff: if(restricted, do: {today.year - 1, today.month})
    }
  end

  def in_window?(_row, nil), do: true

  def in_window?(%{year: year, month: month}, {cut_year, cut_month}),
    do: year > cut_year or (year == cut_year and month >= cut_month)

  def index(user, context, store_geodata, now) do
    rows =
      query(
        """
        SELECT year, month, distance, toponyms, (updated_at AT TIME ZONE 'UTC' AT TIME ZONE $2)::date
        FROM stats WHERE user_id = $1 ORDER BY year DESC, updated_at DESC
        """,
        [user.id, context.zone],
        fn [year, month, distance, toponyms, updated_on] ->
          %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Toponyms.sanitize(toponyms),
            updated_on: updated_on
          }
        end
      )

    years =
      rows
      |> Enum.filter(&in_window?(&1, context.cutoff))
      |> Enum.chunk_by(& &1.year)
      |> Enum.map(fn [first | _] = stats ->
        %{
          year: first.year,
          updated_on: first.updated_on,
          stats: stats,
          distances: distances(stats)
        }
      end)

    toponyms = Enum.flat_map(rows, & &1.toponyms)

    %{
      years: years,
      locked_years: locked(rows, years, context.restricted),
      total_distance: rows |> Enum.map(& &1.distance) |> Enum.sum(),
      countries_visited: Toponyms.countries(toponyms),
      cities_visited: Toponyms.cities(toponyms),
      points: points(user.points_count || 0, PointCounts.fetch(user.id, store_geodata, now))
    }
  end

  def year(user, year, context) do
    rows =
      query(
        "SELECT month, distance, toponyms FROM stats WHERE user_id = $1 AND year = $2 ORDER BY month",
        [user.id, year],
        fn [month, distance, toponyms] ->
          %{year: year, month: month, distance: distance, toponyms: Toponyms.sanitize(toponyms)}
        end
      )

    %{distances: distances(rows), stats: Enum.filter(rows, &in_window?(&1, context.cutoff))}
  end

  def month(user, year, month, context) do
    rows =
      """
      SELECT month, distance, flight_distance, daily_distance, toponyms, sharing_settings, sharing_uuid::text
      FROM stats WHERE user_id = $1 AND year = $2
      """
      |> query([user.id, year], fn [m, distance, flight, daily, toponyms, sharing, uuid] ->
        %{
          year: year,
          month: m,
          distance: distance,
          flight_distance: flight,
          daily: daily(daily),
          toponyms: Toponyms.sanitize(toponyms),
          sharing: sharing(sharing),
          sharing_uuid: uuid
        }
      end)
      |> Enum.filter(&in_window?(&1, context.cutoff))

    %{
      stat: Enum.find(rows, &(&1.month == month)),
      previous: if(month > 1, do: Enum.find(rows, &(&1.month == month - 1))),
      average_km: average_km(rows)
    }
  end

  def daily(list) when is_list(list),
    do: for([day, meters] <- list, is_integer(day) and is_number(meters), do: [day, meters])

  def daily(%{} = map) do
    for {key, meters} <- Enum.sort_by(map, fn {key, _} -> {byte_size(key), key} end),
        {day, ""} <- [Integer.parse(key)],
        is_number(meters),
        do: [day, meters]
  end

  def daily(_other), do: []

  defp distances(stats),
    do: for(month <- 1..12, do: Enum.find_value(stats, 0, &(&1.month == month and &1.distance)))

  defp locked(_rows, _years, false), do: []

  defp locked(rows, years, true),
    do:
      rows
      |> Enum.map(& &1.year)
      |> Enum.uniq()
      |> Kernel.--(Enum.map(years, & &1.year))
      |> Enum.sort(:desc)

  defp points(total, counts),
    do: Map.merge(counts, %{total: total, percentage: percentage(counts.geocoded, total)})

  defp percentage(_geocoded, 0), do: 0.0
  defp percentage(geocoded, total), do: min(RubyFloat.round(geocoded * 100.0 / total, 1), 100.0)

  defp average_km([]), do: 0

  defp average_km(rows),
    do: rows |> Enum.map(& &1.distance) |> Enum.sum() |> div(length(rows)) |> div(1000)

  defp sharing(%{} = settings),
    do: %{enabled: settings["enabled"] == true, expiration: settings["expiration"]}

  defp sharing(_settings), do: %{enabled: false, expiration: nil}

  defp query(sql, params, row), do: Repo.query!(sql, params).rows |> Enum.map(row)
end
