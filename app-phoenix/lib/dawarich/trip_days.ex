defmodule Dawarich.TripDays do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo
  alias Dawarich.Trips.{DeviceWindows, Queries}

  def span_sql(started, ended, zone) do
    """
    SELECT l.sl, l.el,
           extract(epoch FROM (#{ended} AT TIME ZONE 'UTC') - l.p)::bigint AS seconds,
           ((l.p - interval '24 hours') AT TIME ZONE #{zone}) - ((l.p - interval '24 hours') AT TIME ZONE 'UTC')
             <> ((l.p + interval '24 hours') AT TIME ZONE #{zone}) - ((l.p + interval '24 hours') AT TIME ZONE 'UTC')
             AS near_transition
    FROM (SELECT (#{started} AT TIME ZONE 'UTC') AT TIME ZONE #{zone} AS sl,
                 (#{ended} AT TIME ZONE 'UTC') AT TIME ZONE #{zone} AS el,
                 ((((#{ended} AT TIME ZONE 'UTC') AT TIME ZONE #{zone}) - interval '1 month') AT TIME ZONE #{zone}) AS p) l
    """
  end

  def local_span(started, ended, zone) do
    [[started_local, ended_local, seconds, near_transition]] =
      Repo.query!(span_sql("$1::timestamp", "$2::timestamp", "$3::text"), [started, ended, zone]).rows

    span(started_local, ended_local, seconds, near_transition)
  end

  def span(started_local, ended_local, seconds, near_transition) do
    %{
      started_local: started_local,
      ended_local: ended_local,
      previous_month_days: div(seconds, 86_400),
      near_transition: near_transition
    }
  end

  def duration_parts(%NaiveDateTime{} = s, %NaiveDateTime{} = e, previous_month_days) do
    {hours, days} = borrow(e.hour - s.hour, e.day - s.day, 24)
    borrowed = days < 0
    {days, months} = borrow(days, e.month - s.month, previous_month_days)
    {months, years} = borrow(months, e.year - s.year, 12)

    parts =
      for {n, key} <- [{years, "years"}, {months, "months"}, {days, "days"}, {hours, "hours"}],
          n > 0,
          do: {key, n}

    {parts, borrowed}
  end

  defp borrow(value, carry, size) when value < 0, do: {value + size, carry - 1}
  defp borrow(value, carry, _size), do: {value, carry}

  def day_data(user_id, from, to, gap, zone) do
    trip = %{user_id: user_id, from: from, to: to}
    rows = Queries.device_windows(Repo, trip, gap)
    windows = DeviceWindows.primary(rows)
    filter = if rows |> Enum.uniq_by(&hd/1) |> length() > 1, do: windows
    %{windows_json: windows_json(windows), stats: Queries.day_stats(Repo, trip, filter, zone)}
  end

  def windows_json(windows) do
    windows
    |> Enum.map(fn {tracker, start_at, end_at} ->
      {:object, [{"tracker_id", tracker}, {"start_at", start_at}, {"end_at", end_at}]}
    end)
    |> Ruby.json()
    |> IO.iodata_to_binary()
  end
end
