defmodule Dawarich.Trips.DayWindow do
  @moduledoc false

  alias Dawarich.{Repo, TripDays, UserTimeZone}

  @limit 31

  @trip """
  SELECT floor(extract(epoch FROM t.started_at))::bigint, floor(extract(epoch FROM t.ended_at))::bigint,
         ((t.started_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date,
         ((t.ended_at AT TIME ZONE 'UTC') AT TIME ZONE z.name)::date, z.name
  FROM trips t CROSS JOIN z WHERE t.id = $1 AND t.user_id = $2
  """

  @notes """
  SELECT n.id, n.noted_at::date, n.body FROM notes n
  WHERE n.attachable_type = 'Trip' AND n.attachable_id = $1 AND n.noted_at IS NOT NULL
    AND n.noted_at::date BETWEEN $2 AND $3
  """

  def limit, do: @limit

  def load(user, id, from, settings) do
    case UserTimeZone.query!(@trip, [id, user.id], Dawarich.UserSettings.get(user)).rows do
      [[started, ended, first, last, zone]] ->
        from = if from && Date.compare(from, first) == :gt, do: from, else: first
        to = Enum.min([Date.add(from, @limit - 1), last], Date)
        stats = stats(user.id, started, ended, settings.minutes * 60, zone)
        notes = notes(id, from, to)

        days =
          if Date.compare(from, last) == :gt,
            do: [],
            else: for(date <- Date.range(from, to), do: day(date, stats, notes))

        {:ok, %{days: days, next: if(Date.compare(to, last) == :lt, do: Date.add(to, 1))}}

      [] ->
        {:error, :not_found}
    end
  end

  defp stats(user_id, started, ended, gap, zone),
    do: TripDays.day_data(user_id, started, ended, gap, zone).stats

  defp notes(id, from, to),
    do:
      Repo.query!(@notes, [id, from, to]).rows
      |> Map.new(fn [note_id, date, body] -> {date, %{id: note_id, date: date, body: body}} end)

  defp day(date, stats, notes), do: %{date: date, stats: stats[date], note: notes[date]}
end
