defmodule DawarichWeb.VisitStreams do
  @moduledoc false
  use Phoenix.Component
  alias Dawarich.Entitlements
  alias Dawarich.Timeline.{Days, DayRows, MonthSummary}
  alias Dawarich.Visits.{WebEffects, WebScope}

  alias DawarichWeb.{
    Chrome,
    TimelineEntries,
    TimelineFeed,
    TimelineCalendar,
    StatsFormat,
    Translate
  }

  def render(action, result, ctx) do
    zone = result.zone
    dates = WebEffects.dates(ctx.repo, result_rows(action, result), zone)
    date = date(action, result, dates, ctx, zone)
    restricted = not Entitlements.full_access?(ctx.user, ctx.self_hosted, ctx.now, ctx.repo)
    window_now = if restricted, do: ctx.now
    window = window(ctx.repo, zone, date)
    feed = Days.load(ctx.user, window, window_now, ctx.repo)

    frame_ctx = %{
      csrf: ctx.csrf,
      api_key: ctx.user.api_key || "",
      redetected: feed.redetected,
      alert_href:
        if(restricted,
          do:
            StatsFormat.upgrade_url(
              ctx.user,
              ctx.now,
              ctx.self_hosted,
              "data_window",
              "timeline_feed"
            )
        )
    }

    day = List.first(feed.days)
    entry = if action == :update, do: entry(ctx, result.visit)

    calendar =
      if action != :merge,
        do:
          MonthSummary.build(
            ctx.user,
            Date.to_iso8601(date) |> String.slice(0, 7),
            window_now,
            ctx.now,
            ctx.repo
          )

    assigns = %{
      action: action,
      result: result,
      entry: entry,
      day: day,
      calendar: calendar,
      include_day: action != :bulk_destroy or length(dates) == 1,
      locale: ctx.locale,
      ctx: frame_ctx,
      message: notice(action, result, ctx.locale),
      __changed__: nil
    }

    response(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  def notice(:update, result, locale),
    do:
      Translate.t(
        locale,
        "controllers.visits.visit_updated." <>
          Enum.at(~w(suggested confirmed declined), result.visit["status"]),
        %{}
      )

  def notice(:destroy, _result, locale),
    do: Translate.t(locale, "controllers.visits.visit_removed", %{})

  def notice(:merge, _result, locale),
    do: Translate.t(locale, "controllers.visits.visits_merged", %{})

  def notice(:bulk_update, result, locale),
    do:
      Translate.t(locale, "controllers.visits.bulk_updated." <> result.status, %{
        count: result.count
      })

  def notice(:bulk_destroy, result, locale),
    do: Translate.t(locale, "controllers.visits.bulk_removed", %{count: result.count})

  def error(locale, key) do
    flash(%{
      locale: locale,
      type: "error",
      message: Translate.t(locale, "controllers.visits." <> key, %{}),
      __changed__: nil
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp result_rows(action, result) when action in [:update, :destroy], do: [result.visit]
  defp result_rows(_action, result), do: result.rows

  defp date(:bulk_update, %{date: value}, _dates, ctx, zone) when value in [nil, ""],
    do: today(ctx, zone)

  defp date(:bulk_update, result, _dates, _ctx, _zone), do: Date.from_iso8601!(result.date)
  defp date(:bulk_destroy, _result, [_ | [_ | _]], ctx, zone), do: today(ctx, zone)
  defp date(_action, _result, [date | _], _ctx, _zone), do: date

  defp today(ctx, zone),
    do: WebEffects.dates(ctx.repo, [%{"started_at" => DateTime.to_naive(ctx.now)}], zone) |> hd()

  defp window(repo, zone, date) do
    {:ok, {first, last}} = WebScope.day_bounds(zone, Date.to_iso8601(date), repo)

    %{
      start: DateTime.from_naive!(first, "Etc/UTC") |> DateTime.to_iso8601(),
      end:
        DateTime.from_naive!(last, "Etc/UTC")
        |> DateTime.add(-1, :microsecond)
        |> DateTime.to_iso8601(),
      start_date: date,
      end_date: date
    }
  end

  defp entry(ctx, visit) do
    rows = DayRows.visit(ctx.user, visit["id"], ctx.repo)
    row = Enum.find(rows.visits, &(&1.id == visit["id"]))
    Days.entry(row, rows)
  end

  defp response(assigns) do
    ~H"""
    <turbo-stream
      :if={@action == :update}
      action="replace"
      target={"visit_entry_#{@result.visit["id"]}"}
    >
      <template><TimelineEntries.visit_entry entry={@entry} locale={@locale} ctx={@ctx} /></template>
    </turbo-stream>
    <turbo-stream
      :if={@action == :destroy}
      action="remove"
      target={"visit_entry_#{@result.visit["id"]}"}
    >
    </turbo-stream>
    <turbo-stream
      :if={@action in [:bulk_update, :bulk_destroy, :merge] and @include_day}
      action="update"
      target="timeline-feed-frame"
    >
      <template><TimelineFeed.day :if={@day} day={@day} locale={@locale} ctx={@ctx} /></template>
    </turbo-stream>
    <turbo-stream :if={@action != :merge} action="replace" target="timeline-calendar-frame">
      <template><TimelineCalendar.calendar summary={@calendar} locale={@locale} /></template>
    </turbo-stream>
    <.flash locale={@locale} type="notice" message={@message} />
    """
  end

  defp flash(assigns) do
    ~H"""
    <turbo-stream action="append" target="flash-messages">
      <template><Chrome.flash_message type={@type} message={@message} locale={@locale} /></template>
    </turbo-stream>
    """
  end
end
