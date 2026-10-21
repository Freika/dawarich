defmodule Dawarich.Maps.Timeline do
  @moduledoc false
  alias Dawarich.{MapWindow, Maps, RubyInteger}
  alias Dawarich.Visits.Timeline, as: Source
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Formatting.StatsFormat

  @bounds ~w(start_at end_at)

  def feed(scope, params, opts \\ []) when is_map(params) do
    if Enum.all?(@bounds, &(is_nil(params[&1]) or is_binary(params[&1]))) do
      Maps.with_actor(scope, fn actor ->
        now = now(opts)
        window = MapWindow.build(bounds(params, now), Dawarich.UserSettings.get(actor), now, nil)

        query = %{
          "start_at" => window.start,
          "end_at" => window.end,
          "cursor" => params["cursor"]
        }

        with {:ok, page} <- Source.load(scope, query, source_options(opts)) do
          entries = Enum.group_by(page.rows, & &1.date)
          days = Enum.map(page.days, &Map.put(&1, :entries, Map.get(entries, &1.date, [])))

          {:ok,
           %{
             days: days,
             redetected: page.redetected,
             requested_date: window.start_date,
             restricted: page.restricted,
             alert_href: alert_href(page.restricted, actor, now, opts),
             unit: Dawarich.Timeline.Days.unit(Dawarich.UserSettings.get(actor)),
             next_cursor: page.next_cursor,
             revision: page.revision,
             stream_limit: page.stream_limit
           }}
        end
      end)
    else
      {:error, :invalid}
    end
  end

  def track(scope, id) do
    Maps.with_actor(scope, fn actor ->
      case Dawarich.Timeline.DayRows.track(actor, RubyInteger.to_i(id)) do
        nil -> {:error, :not_found}
        track -> {:ok, track}
      end
    end)
  end

  def calendar(scope, month, opts \\ []) do
    with {:ok, _} <- Maps.admit(scope, opts) do
      case Source.calendar(scope, month, source_options(opts)) do
        {:error, :invalid_input} -> {:error, :invalid}
        result -> result
      end
    end
  end

  defp bounds(params, now) do
    Map.new(@bounds, fn key ->
      value = params[key]
      {key, if(Ruby.blank?(value), do: Integer.to_string(DateTime.to_unix(now)), else: value)}
    end)
  end

  defp alert_href(false, _actor, _now, _opts), do: nil

  defp alert_href(_restricted, actor, now, opts),
    do:
      StatsFormat.upgrade_url(
        actor,
        now,
        source_options(opts)[:self_hosted],
        "data_window",
        "timeline_feed"
      )

  defp source_options(opts),
    do:
      Keyword.put(
        opts,
        :self_hosted,
        Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
      )

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
end
