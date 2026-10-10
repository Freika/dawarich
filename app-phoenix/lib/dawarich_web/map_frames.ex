defmodule DawarichWeb.MapFrames do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Entitlements, MapWindow, PlaceDrawer, PointList, TrackSegmentPage}
  alias Dawarich.Timeline.{DayRows, Days, MonthSummary}

  alias DawarichWeb.{
    LayoutAssigns,
    PlaceDrawerFrame,
    PointAddressFrame,
    SegmentFrame,
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
      track_id: conn.path_params["track_id"],
      now: DateTime.utc_now(),
      self_hosted: LayoutAssigns.self_hosted?(),
      csrf: csrf,
      csrf_changes: csrf_changes,
      stream: action == :calendar and stream?(accept)
    }

    result =
      if action == :residency and restricted?(ctx), do: :pro_required, else: body(action, ctx)

    case result do
      :pro_required ->
        reject_pro(conn)

      {:ok, type, html} ->
        respond(conn, accept, type, html)

      {:ok, type, html, changes} ->
        conn |> RailsSession.stage(changes) |> respond(accept, type, html)

      {:error, status} ->
        DawarichWeb.RailsErrors.respond(conn, status)

      :not_found ->
        raise DawarichWeb.NotFoundError

      {:replay, reason} ->
        conn
        |> assign(:api_tag, replay_tag(action))
        |> Body.replay(reason)
    end
  end

  def body(:index, %{query: %{"start_at" => value}})
      when not is_binary(value) and not is_nil(value),
      do: {:error, 500}

  def body(:index, %{query: %{"end_at" => value}})
      when not is_binary(value) and not is_nil(value),
      do: {:error, 500}

  def body(:index, ctx) do
    window =
      MapWindow.build(
        Map.new(~w(start_at end_at), fn key ->
          value = ctx.query[key]

          {key,
           if(Dawarich.ReleaseMigrations.Effects.Support.Ruby.blank?(value),
             do: Integer.to_string(DateTime.to_unix(ctx.now)),
             else: value
           )}
        end),
        Dawarich.UserSettings.get(ctx.user),
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
  rescue
    _error in [ArgumentError, FunctionClauseError] -> {:error, 500}
  end

  def body(:residency, %{query: %{"year" => value}})
      when not is_binary(value) and not is_nil(value),
      do: {:error, 500}

  def body(:residency, ctx) do
    year = if is_binary(ctx.query["year"]), do: DawarichWeb.Params.ruby_to_i(ctx.query["year"])

    case ResidencyFrame.data(ctx.user, year, ctx.now) do
      {:ok, data} -> html(&ResidencyFrame.frame/1, Map.put(data, :locale, ctx.locale))
      {:error, status} -> {:error, status}
    end
  end

  def body(:track_info, ctx) do
    case DayRows.track(ctx.user, String.to_integer(ctx.id)) do
      nil ->
        :not_found

      track ->
        html(&TimelineCalendar.track_info_frame/1, %{
          track: track,
          unit: Days.unit(Dawarich.UserSettings.get(ctx.user)),
          locale: ctx.locale
        })
    end
  end

  def body(:place, ctx) do
    case PlaceDrawer.load(ctx.user, String.to_integer(ctx.id)) do
      {:ok, drawer} ->
        {:ok, type, html} =
          html(&PlaceDrawerFrame.frame/1, %{drawer: drawer, locale: ctx.locale, csrf: ctx.csrf})

        if ctx.csrf_changes == %{},
          do: {:ok, type, html},
          else: {:ok, type, html, ctx.csrf_changes}

      :rails ->
        {:replay, "place drawer changed after the gate"}
    end
  end

  def body(:segments, ctx) do
    case TrackSegmentPage.load(ctx.user, String.to_integer(ctx.track_id)) do
      {:ok, data} ->
        {:ok, type, html} =
          html(
            &SegmentFrame.frame/1,
            Map.merge(data, %{
              user: ctx.user,
              locale: ctx.locale,
              csrf: ctx.csrf,
              now: ctx.now,
              unit: Days.unit(Dawarich.UserSettings.get(ctx.user))
            })
          )

        if data.segments == [] or ctx.csrf_changes == %{},
          do: {:ok, type, html},
          else: {:ok, type, html, ctx.csrf_changes}

      :rails ->
        {:replay, "segments changed after the gate"}
    end
  end

  def body(:point_address, ctx) do
    case PointList.address(ctx.user, String.to_integer(ctx.id)) do
      {:ok, point} -> html(&PointAddressFrame.frame/1, %{point: point, locale: ctx.locale})
      :rails -> {:replay, "point address changed after the gate"}
    end
  end

  defp reject_pro(conn) do
    alert =
      DawarichWeb.Translate.t(
        conn.assigns.locale,
        "controllers.application.this_feature_requires_a_pro_plan",
        %{}
      )

    location = DawarichWeb.RailsRedirect.back(conn)

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => alert}}})
    |> put_resp_header("location", location)
    |> put_resp_content_type("text/html")
    |> send_resp(303, "")
  end

  defp replay_tag(:place), do: "places"
  defp replay_tag(:segments), do: "tracks"
  defp replay_tag(:point_address), do: "points"
  defp replay_tag(_), do: "map"

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

  defp csrf(%{"_csrf_token" => token} = session, action)
       when action in [:index, :place, :segments] and is_binary(token),
       do: {RailsCsrf.masked_token(session), %{}}

  defp csrf(_session, action) when action in [:index, :place, :segments] do
    token = RailsCsrf.new_token()
    {RailsCsrf.masked_token(%{"_csrf_token" => token}), %{"_csrf_token" => token}}
  end

  defp csrf(_session, _action), do: {nil, %{}}
end
