defmodule DawarichWeb.ShareManagementPage do
  @moduledoc false

  import Plug.Conn
  alias Dawarich.ShareManagement.Read
  alias DawarichWeb.{LayoutAssigns, Layouts, ShareHub, ShareManagementDocument, Translate}

  def init(action), do: action

  def call(conn, :hub) do
    conn = LayoutAssigns.call(conn, [])
    render(conn, :hub)
  end

  def call(conn, action) when action in [:live, :trip],
    do: conn |> LayoutAssigns.call([]) |> render(action)

  def render(conn, :hub) do
    {:ok, hub} = Read.hub(conn.assigns.current_user, conn.query_params, conn.assigns.now)
    ctx = context(conn)
    content = ShareHub.frame(%{__changed__: nil, hub: hub, ctx: ctx, errors: []})
    respond(conn, content)
  end

  def render(conn, action) when action in [:live, :trip] do
    user = conn.assigns.current_user
    now = conn.assigns.now

    result =
      if action == :live,
        do: Read.live(user, now),
        else: Read.trip(user, String.to_integer(conn.path_params["trip_id"]), now)

    case result do
      {:ok, page} ->
        content =
          ShareManagementDocument.frame(%{
            __changed__: nil,
            page: page,
            ctx: context(conn),
            type: to_string(action)
          })

        respond(conn, content)

      {:error, 404} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          404,
          Translate.t(conn.assigns.locale, "controllers.trips.share_links.not_found", %{})
        )
    end
  end

  def context(conn) do
    %{
      user_id: conn.assigns.current_user.id,
      locale: conn.assigns.locale,
      csrf: conn.assigns.rails_csrf_token,
      settings: Dawarich.UserSettings.get(conn.assigns.current_user),
      now: conn.assigns.now,
      base_url: conn.assigns.base_url,
      phrase: &Read.phrase/0
    }
  end

  def respond(conn, content, status \\ 200) do
    html =
      if get_req_header(conn, "turbo-frame") == ["share-link-modal"] do
        content
      else
        user = conn.assigns.current_user

        assigns =
          Map.merge(conn.assigns, %{
            __changed__: nil,
            page_title: nil,
            rails_js: true,
            rails_charts: false,
            flash: %{},
            navbar:
              Dawarich.Navbar.load(user,
                now: conn.assigns.now,
                self_hosted: conn.assigns.self_hosted
              )
          })

        app = Layouts.app(Map.put(assigns, :inner_content, content))
        Layouts.root(Map.put(assigns, :inner_content, app))
      end

    conn
    |> vary()
    |> put_resp_content_type("text/html")
    |> send_resp(status, Phoenix.HTML.Safe.to_iodata(html))
  end

  defp vary(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")

    if String.trim(accept) != "" and not DawarichWeb.Strangler.browser_like?(accept),
      do: put_resp_header(conn, "vary", "Accept"),
      else: conn
  end
end
