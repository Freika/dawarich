defmodule Dawarich.Visits.Timeline do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Timeline.{DayRows, Days, MonthSummary, Query, Summary}
  alias Dawarich.{Entitlements, Repo}

  def calendar(scope, month, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    hosted =
      Keyword.get(opts, :self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))

    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         :ok <- month_shape(month, now) do
      cutoff = if not Entitlements.full_access?(scope.user, hosted, now), do: now
      {:ok, MonthSummary.build(scope.user, month, cutoff, now)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp month_shape(month, _now) when month in [nil, ""], do: :ok

  defp month_shape(month, _now) when is_binary(month) and byte_size(month) <= 128 do
    case Date.from_iso8601(month <> "-01") do
      {:ok, _date} -> :ok
      _ -> {:error, :invalid_input}
    end
  end

  defp month_shape(_, _), do: {:error, :invalid_input}

  def load(scope, params, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    hosted =
      Keyword.get(opts, :self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))

    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         restricted = not Entitlements.full_access?(scope.user, hosted, now),
         {:ok, query} <- Query.normalize(scope.user, params, now, restricted) do
      keys = Query.keys(scope.user, query, Repo)
      visible = Enum.take(keys, 100)
      loaded = DayRows.fetch_window(scope.user, query, visible, Repo)
      unit = Days.unit(Dawarich.UserSettings.get(scope.user))
      days = Days.build(loaded, unit)
      entries = for day <- days, entry <- day.entries, do: Map.put(entry, :date, day.date)

      rows =
        Enum.map(visible, fn [day, _, _, kind, id] ->
          Enum.find(entries, fn e ->
            e.date == Date.to_iso8601(day) and
              if(kind == 0, do: e[:visit_id] == -id, else: e[:track_id] == id)
          end)
        end)

      summaries = Summary.load(scope.user, query, unit, Repo)
      bounds = Summary.bounds(scope.user, query, Repo)

      days =
        Enum.map(summaries, fn {date, summary} ->
          %{date: date, summary: summary, bounds: Map.get(bounds, date)}
        end)
        |> Enum.sort_by(& &1.date)

      calendar =
        MonthSummary.build(
          scope.user,
          Calendar.strftime(query.window.start_date, "%Y-%m"),
          query.cutoff,
          now
        )

      {:ok,
       %{
         rows: rows,
         days: days,
         calendar: calendar,
         restricted: restricted,
         redetected: loaded.redetected,
         window: query.window,
         revision: query.fingerprint,
         next_cursor:
           if(length(keys) > 100, do: Query.next(List.last(visible), query.fingerprint)),
         stream_limit: 200,
         reset: is_nil(query.cursor)
       }}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
