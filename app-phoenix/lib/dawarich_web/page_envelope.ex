defmodule DawarichWeb.PageEnvelope do
  @moduledoc false
  import Plug.Conn

  @pipelines ~w(browser insights rails_frame sharing achievement_public trial_resume trial_welcome public_home standalone_settings achievement_image native_navigation family_form user_data_export native_share)a
  @turbo "text/vnd.turbo-stream.html"
  @calendar "/map/timeline_feeds/calendar"
  @redirects ~w(/ /settings/theme /trial/upgrade /trial/welcome)
  def init(opts), do: opts

  def prepare(conn) do
    if Dawarich.Standalone.enabled?() and conn.method in ~w(GET HEAD),
      do: normalize(conn),
      else: conn
  end

  defp normalize(conn) do
    {path, format} = path_format(conn)
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    case Phoenix.Router.route_info(DawarichWeb.Router, method, path, conn.host) do
      %{pipe_through: pipelines} = route ->
        if Enum.any?(pipelines, &(&1 in @pipelines)) do
          query = Plug.Conn.Query.decode(conn.query_string)
          selected = format || query["format"]
          navigation = :native_navigation in pipelines

          if navigation or selected in [nil, "html", "turbo_stream"] do
            conn
            |> put_private(:dawarich_page_envelope, true)
            |> put_private(:dawarich_page_format, selected)
            |> put_private(:dawarich_page_accept, get_req_header(conn, "accept"))
            |> put_private(:dawarich_page_frame, frame?(conn))
            |> put_private(:dawarich_page_route, route)
            |> put_private(:dawarich_page_original, {conn.request_path, conn.query_string})
            |> Map.put(:path_info, path)
            |> Map.put(:request_path, "/" <> Enum.join(path, "/"))
            |> Map.put(:query_string, without_format(conn.query_string))
            |> html_accept(selected, navigation or conn.request_path in @redirects)
            |> frame_header(route)
          else
            conn
          end
        else
          conn
        end

      _ ->
        conn
    end
  rescue
    Plug.Conn.InvalidQueryError -> conn
  end

  defp path_format(conn) do
    path = conn.path_info

    case Regex.run(~r/\A(.+)\.([^\.\/]+)\z/, List.last(path) || "") do
      [_, name, format] ->
        candidate = List.replace_at(path, -1, name)
        method = if conn.method == "HEAD", do: "GET", else: conn.method

        if Phoenix.Router.route_info(DawarichWeb.Router, method, candidate, conn.host) == :error,
          do: {path, nil},
          else: {candidate, format}

      _ ->
        {path, nil}
    end
  end

  defp without_format(query) do
    query
    |> String.split("&", trim: true)
    |> Enum.reject(fn part ->
      part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form() == "format"
    end)
    |> Enum.join("&")
  end

  defp html_accept(conn, "html", _), do: put_req_header(conn, "accept", "text/html")
  defp html_accept(conn, _, true), do: put_req_header(conn, "accept", "text/html")

  defp html_accept(conn, "turbo_stream", _),
    do: put_req_header(conn, "accept", @turbo)

  defp html_accept(conn, _, _) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")
    formats = DawarichWeb.PageAccept.formats(accept, xhr_header?(conn))

    if formats == :invalid_type do
      conn |> put_resp_content_type("text/plain") |> send_resp(406, "") |> halt()
    else
      available =
        if conn.request_path == @calendar,
          do: ~w(text/vnd.turbo-stream.html text/html),
          else: ~w(text/html)

      type = DawarichWeb.PageAccept.negotiate(formats, available)
      fallback = formats == ["text/javascript"]

      conn
      |> put_private(:dawarich_page_formats, formats)
      |> put_private(:dawarich_page_bare, fallback)
      |> put_private(:dawarich_page_xhr_js, fallback)
      |> put_private(:dawarich_page_template_missing, is_nil(type))
      |> put_req_header("accept", type || "text/html")
    end
  end

  def accepted?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")

    formats =
      conn.private[:dawarich_page_formats] ||
        DawarichWeb.PageAccept.formats(accept, xhr_header?(conn))

    valued =
      conn.query_string |> String.split("&", trim: true) |> Enum.all?(&String.contains?(&1, "="))

    valued and
      Enum.any?(formats, &(&1 in ~w(text/html text/javascript */* text/vnd.turbo-stream.html)))
  end

  def authenticate_first?(conn, route) do
    conn.private[:dawarich_page_envelope] == true and
      Enum.any?(
        route.pipe_through,
        &(&1 in [:rails_user, :rails_frame, :insights, :trial_resume])
      ) and
      is_nil(DawarichWeb.RailsAuth.call(conn, []).assigns.current_user)
  end

  def xhr?(conn) do
    conn.private[:dawarich_page_envelope] == true and
      xhr_header?(conn)
  end

  def unauthorized(conn, message) do
    type =
      cond do
        conn.private[:dawarich_page_format] == "html" ->
          "text/html"

        conn.private[:dawarich_page_xhr_js] ->
          "text/javascript"

        conn.private[:dawarich_page_accept] == [@turbo] ->
          @turbo

        true ->
          "text/html"
      end

    conn |> put_resp_content_type(type) |> send_resp(401, message) |> halt()
  end

  def original_target(conn),
    do: conn.private[:dawarich_page_original] || {conn.request_path, conn.query_string}

  def document(conn, assigns, content) do
    assigns = Map.put(assigns, :inner_content, content)

    cond do
      conn.private[:dawarich_page_bare] ->
        content

      conn.private[:dawarich_page_envelope] == true and frame?(conn) ->
        DawarichWeb.InsightsFrameLayout.render(assigns)

      true ->
        DawarichWeb.Layouts.root(
          Map.put(assigns, :inner_content, DawarichWeb.Layouts.app(assigns))
        )
    end
  end

  def live_options(conn, opts) do
    if conn.private[:dawarich_page_envelope] == true and
         (frame?(conn) or conn.private[:dawarich_page_bare]),
       do: Keyword.put(opts, :layout, false),
       else: opts
  end

  def navigation?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def call(conn, :navigation) do
    body =
      %{
        "/recede_historical_location" => "Going back…",
        "/resume_historical_location" => "Staying put…",
        "/refresh_historical_location" => "Refreshing…"
      }[conn.request_path]

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, if(conn.private[:dawarich_method] == "HEAD", do: "", else: body))
  end

  def call(conn, :router) do
    conn =
      if conn.private[:dawarich_page_envelope] == true and
           ((turbo_only?(conn) and conn.request_path != @calendar) or
              (conn.private[:dawarich_page_template_missing] == true and
                 (not conn.private[:dawarich_page_xhr_js] or
                    conn.request_path == @calendar))) do
        conn
        |> put_req_header("accept", "text/html")
        |> register_before_send(&refuse_template/1)
      else
        conn
      end

    DawarichWeb.Router.call(conn, DawarichWeb.Router.init([]))
  end

  def call(conn, :layout) do
    cond do
      conn.private[:dawarich_page_bare] ->
        conn |> Phoenix.Controller.put_root_layout(false) |> live_frame(false)

      conn.private[:dawarich_page_envelope] == true and frame?(conn) and
          conn.request_path not in ~w(/map /map/v2) ->
        layout = {DawarichWeb.InsightsFrameLayout, :render}
        conn |> Phoenix.Controller.put_root_layout(layout) |> live_frame(layout)

      true ->
        conn
    end
  end

  defp turbo_only?(conn) do
    conn.private[:dawarich_page_format] == "turbo_stream" or
      (conn.private[:dawarich_page_formats] == [@turbo] or
         get_req_header(conn, "accept") == [@turbo])
  end

  defp refuse_template(%{status: status} = conn) when status in [200, 202] do
    route = conn.private.dawarich_page_route

    if get_resp_header(conn, "content-disposition") != [] or
         conn.request_path in @redirects or :native_navigation in route.pipe_through or
         :achievement_image in route.pipe_through do
      conn
    else
      status =
        if conn.request_path in ~w(/map/residency /places/nearby) or
             route.plug == DawarichWeb.SharedStatsPage,
           do: 500,
           else: 406

      %{conn | status: status, resp_body: ""}
    end
  end

  defp refuse_template(conn), do: conn

  defp live_frame(%{private: %{phoenix_live_view: {view, opts, session}}} = conn, layout) do
    extra =
      session.extra
      |> Map.put(:root_layout, layout)
      |> Map.put(:layout, false)

    put_private(
      conn,
      :phoenix_live_view,
      {view, Keyword.put(opts, :layout, false), %{session | extra: extra}}
    )
  end

  defp live_frame(conn, _layout), do: conn

  defp frame_header(conn, route) do
    neutral =
      route.plug in [
        DawarichWeb.AchievementPublicPage,
        DawarichWeb.TrialWelcome,
        DawarichWeb.TrialUpgrade,
        DawarichWeb.HomeDispatch,
        DawarichWeb.ShareManagementPage,
        DawarichWeb.TimelineShareActions,
        DawarichWeb.TrackShareActions
      ] or
        conn.request_path == "/trial/resume"

    place =
      route.plug == DawarichWeb.PlaceNavigation and
        get_req_header(conn, "turbo-frame") != ["place-drawer"]

    if neutral or place, do: delete_req_header(conn, "turbo-frame"), else: conn
  end

  defp xhr_header?(conn),
    do:
      Enum.any?(get_req_header(conn, "x-requested-with"), &String.match?(&1, ~r/XMLHttpRequest/i))

  def frame?(%{private: %{dawarich_page_frame: frame}}), do: frame
  def frame?(conn), do: Enum.any?(get_req_header(conn, "turbo-frame"), &(String.trim(&1) != ""))
end
