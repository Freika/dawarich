defmodule DawarichWeb.MapFrames do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Entitlements, MapWindow}
  alias Dawarich.Timeline.{DayRows, Days, MonthSummary}

  alias DawarichWeb.{
    LayoutAssigns,
    RailsCsrf,
    RailsSession,
    ResidencyFrame,
    StatsFormat,
    Strangler,
    TimelineCalendar,
    TimelineFeed
  }

  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")
    {csrf, csrf_changes} = csrf(conn.assigns.rails_session, action)

    ctx = %{
      user: conn.assigns.current_user,
      locale: conn.assigns.locale,
      query: conn.query_params,
      id: conn.path_params["id"],
      now: DateTime.utc_now(),
      self_hosted: LayoutAssigns.self_hosted?(),
      csrf: csrf,
      csrf_changes: csrf_changes,
      stream: action == :calendar and stream?(accept)
    }

    case body(action, ctx) do
      {:ok, type, html} ->
        respond(conn, accept, type, html)

      {:ok, type, html, changes} ->
        conn |> RailsSession.stage(changes) |> respond(accept, type, html)

      :not_found ->
        raise DawarichWeb.NotFoundError

      {:replay, reason} ->
        conn |> assign(:api_tag, "map") |> Body.replay(reason)
    end
  end

  def body(:index, ctx) do
    window =
      MapWindow.build(
        Map.take(ctx.query, ["start_at", "end_at"]),
        ctx.user.settings || %{},
        ctx.now,
        nil
      )

    restricted = restricted?(ctx)
    feed = Days.load(ctx.user, window, if(restricted, do: ctx.now))

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

    {:ok, type, html} =
      html(&TimelineFeed.frame/1, %{
        days: feed.days,
        requested_date: window.start_date,
        locale: ctx.locale,
        ctx: frame_ctx
      })

    if feed.days == [] or ctx.csrf_changes == %{},
      do: {:ok, type, html},
      else: {:ok, type, html, ctx.csrf_changes}
  end

  def body(:calendar, ctx) do
    summary =
      MonthSummary.build(ctx.user, ctx.query["month"], if(restricted?(ctx), do: ctx.now), ctx.now)

    assigns = %{summary: summary, locale: ctx.locale}

    if ctx.stream,
      do: render(&TimelineCalendar.calendar_stream/1, assigns, "text/vnd.turbo-stream.html"),
      else: html(&TimelineCalendar.calendar/1, assigns)
  end

  def body(:residency, ctx) do
    year = if is_binary(ctx.query["year"]), do: String.to_integer(ctx.query["year"])

    case ResidencyFrame.data(ctx.user, year, ctx.now) do
      {:ok, data} -> html(&ResidencyFrame.frame/1, Map.put(data, :locale, ctx.locale))
      {:replay, reason} -> {:replay, reason}
    end
  end

  def body(:track_info, ctx) do
    case DayRows.track(ctx.user, String.to_integer(ctx.id)) do
      nil ->
        :not_found

      track ->
        html(&TimelineCalendar.track_info_frame/1, %{
          track: track,
          unit: Days.unit(ctx.user.settings),
          locale: ctx.locale
        })
    end
  end

  def stream?(accept),
    do:
      String.trim(accept) != "" and not Strangler.browser_like?(accept) and
        (accept |> String.split(",") |> hd() |> String.trim()) in [
          "text/vnd.turbo-stream.html",
          "*/*"
        ]

  defp restricted?(ctx), do: not Entitlements.full_access?(ctx.user, ctx.self_hosted, ctx.now)

  defp html(fun, assigns), do: render(fun, assigns, "text/html")

  defp render(fun, assigns, type),
    do:
      {:ok, type,
       assigns |> Map.put(:__changed__, nil) |> fun.() |> Phoenix.HTML.Safe.to_iodata()}

  defp respond(conn, accept, type, html),
    do: conn |> vary(accept) |> put_resp_content_type(type) |> send_resp(200, html)

  defp vary(conn, accept) do
    if String.trim(accept) != "" and not Strangler.browser_like?(accept),
      do: put_resp_header(conn, "vary", "Accept"),
      else: conn
  end

  defp csrf(%{"_csrf_token" => token} = session, :index) when is_binary(token),
    do: {RailsCsrf.masked_token(session), %{}}

  defp csrf(_session, :index) do
    token = RailsCsrf.new_token()
    {RailsCsrf.masked_token(%{"_csrf_token" => token}), %{"_csrf_token" => token}}
  end

  defp csrf(_session, _action), do: {nil, %{}}
end
