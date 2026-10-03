defmodule Dawarich.Timeline.MonthSummary do
  @moduledoc false

  import Dawarich.Timeline.Sql

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.UserTimeZone

  @bounds """
  CROSS JOIN LATERAL (
    SELECT ($2::date::timestamp AT TIME ZONE z.name) AT TIME ZONE 'UTC' AS first,
           (($2::date + interval '1 month' - interval '1 microsecond') AT TIME ZONE z.name) AT TIME ZONE 'UTC' AS last
  ) m
  """

  @empty %{tracked_seconds: 0, track_count: 0, point_count: 0, visit_count: 0, suggested_count: 0}

  def build(user, month, window_now, now) do
    settings = user.settings || %{}
    [[today, cutoff]] = context(now, window_now, settings)

    start =
      if Ruby.blank?(month),
        do: Date.beginning_of_month(today),
        else: Date.from_iso8601!(month <> "-01")

    args = [user.id, start, window_now]

    days =
      %{}
      |> add_visits(UserTimeZone.query!(visits_sql(), args, settings).rows)
      |> add_points(UserTimeZone.query!(points_sql(), args, settings).rows)
      |> add_tracks(UserTimeZone.query!(tracks_sql(), args, settings).rows)

    %{month: Calendar.strftime(start, "%Y-%m"), weeks: weeks(start, days, cutoff)}
  end

  defp context(now, window_now, settings) do
    """
    SELECT ($1::timestamptz AT TIME ZONE z.name)::date,
           CASE WHEN $2::timestamptz IS NULL THEN NULL ELSE (#{window_start("$2")} AT TIME ZONE z.name)::date END
    FROM z
    """
    |> UserTimeZone.query!([now, window_now], settings)
    |> Map.fetch!(:rows)
  end

  defp visits_sql do
    """
    SELECT #{day("v.started_at")}, v.status, count(*), coalesce(sum(v.duration), 0)
    FROM visits v CROSS JOIN z
    #{@bounds}
    WHERE v.user_id = $1 AND v.deleted_at IS NULL AND v.status <> 2
      AND v.started_at BETWEEN m.first AND m.last AND #{windowed("v.started_at", "$3")}
    GROUP BY 1, 2
    """
  end

  defp points_sql do
    """
    SELECT (to_timestamp(p.timestamp) AT TIME ZONE z.name)::date, count(*)
    FROM points p CROSS JOIN z
    #{@bounds}
    WHERE p.user_id = $1
      AND p.timestamp BETWEEN floor(extract(epoch FROM m.first AT TIME ZONE 'UTC'))::bigint
                          AND floor(extract(epoch FROM m.last AT TIME ZONE 'UTC'))::bigint
      AND ($3::timestamptz IS NULL OR p.timestamp >= floor(extract(epoch FROM #{window_start("$3")}))::bigint)
    GROUP BY 1
    """
  end

  defp tracks_sql do
    """
    SELECT t.id, t.duration, #{day("t.start_at")}, #{total("t")}, s.day, s.seconds
    FROM tracks t CROSS JOIN z
    #{@bounds}
    #{shares("t")}
    WHERE t.user_id = $1 AND t.start_at <= m.last AND t.end_at >= m.first AND #{windowed("t.start_at", "$3")}
    ORDER BY t.id, s.day
    """
  end

  defp add_visits(days, rows) do
    Enum.reduce(rows, days, fn [date, status, count, minutes], acc ->
      acc
      |> bump(date, :visit_count, count)
      |> bump(date, :suggested_count, if(status == 0, do: count, else: 0))
      |> bump(date, :tracked_seconds, minutes * 60)
    end)
  end

  defp add_points(days, rows),
    do: Enum.reduce(rows, days, fn [date, count], acc -> bump(acc, date, :point_count, count) end)

  defp add_tracks(days, rows) do
    {seconds, starts} =
      rows
      |> Enum.chunk_by(&hd/1)
      |> Enum.reduce({%{}, %{}}, fn [[_id, duration, start_day, total, _, _] | _] = group,
                                    {seconds, starts} ->
        slices = for [_, _, _, _, day, value] <- group, day != nil, do: {day, value}

        seconds =
          Enum.reduce(shares_of(total, start_day, slices), seconds, fn {day, share}, acc ->
            value = (duration || 0) * share
            Map.update(acc, day, 0.0 + value, &(&1 + value))
          end)

        {seconds, Map.update(starts, start_day, 1, &(&1 + 1))}
      end)

    days =
      Enum.reduce(seconds, days, fn {date, value}, acc ->
        bump(acc, date, :tracked_seconds, trunc(value))
      end)

    Enum.reduce(starts, days, fn {date, count}, acc -> bump(acc, date, :track_count, count) end)
  end

  defp bump(days, date, key, by),
    do:
      Map.update(
        days,
        date,
        Map.update!(@empty, key, &(&1 + by)),
        &Map.update!(&1, key, fn v -> v + by end)
      )

  defp weeks(start, days, cutoff) do
    grid = Date.add(start, 1 - Date.day_of_week(start))

    cells =
      Enum.map(0..41, fn offset ->
        date = Date.add(grid, offset)

        days
        |> Map.get(date, @empty)
        |> Map.merge(%{
          date: Date.to_iso8601(date),
          in_month: date.month == start.month,
          disabled: cutoff != nil and Date.compare(date, cutoff) == :lt
        })
      end)

    peak =
      cells
      |> Enum.filter(& &1.in_month)
      |> Enum.map(& &1.tracked_seconds)
      |> Enum.max(fn -> 0 end)

    cells
    |> Enum.map(&Map.put(&1, :heat_bucket, bucket(&1, peak)))
    |> Enum.chunk_every(7)
  end

  defp bucket(cell, peak) do
    active =
      cell.tracked_seconds > 0 or cell.visit_count > 0 or cell.track_count > 0 or
        cell.point_count > 0

    cond do
      not active -> 0
      peak <= 0 -> 1
      true -> (cell.tracked_seconds / peak * 5) |> Float.ceil() |> trunc() |> max(1) |> min(5)
    end
  end
end
