defmodule DawarichWeb.SharedLinkPage do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.SharedLinks
  alias DawarichWeb.{LayoutAssigns, RailsSession, RequestURL, SharedLinkCookie, SharedPages}
  alias DawarichWeb.Api.{Body, Respond}

  @incorrect "controllers.shared.links.incorrect_phrase"

  @impl true
  def init(action), do: action

  @impl true
  def call(%{path_params: %{"id" => id}} = conn, :show) do
    now = DateTime.utc_now()

    case SharedLinks.active(id, now) do
      nil -> render(conn, 404, %{page: :not_found})
      link -> show(conn, link, now)
    end
  end

  def call(%{path_params: %{"id" => id}} = conn, :unlock) do
    now = DateTime.utc_now()
    phrase = conn.assigns.api_params["phrase"] || ""

    case SharedLinks.active(id, now) do
      nil ->
        conn |> LayoutAssigns.call([]) |> render(404, %{page: :not_found})

      link ->
        if Plug.Crypto.secure_compare(link.magic_phrase || "", phrase) do
          conn
          |> SharedLinkCookie.put(link, SharedLinkCookie.expires_at(link, now, nil))
          |> put_resp_header("location", RequestURL.base(conn) <> "/s/" <> id)
          |> respond(302, "")
        else
          error = DawarichWeb.Translate.t(conn.assigns.locale, @incorrect, %{})

          conn
          |> LayoutAssigns.call([])
          |> render(401, %{page: :phrase_prompt, link: link, error: error})
        end
    end
  end

  defp show(conn, link, now) do
    if SharedLinkCookie.unlocked?(conn, link, now) do
      case SharedLinks.page(link) do
        :rails ->
          conn |> assign(:api_tag, "sharing") |> Body.replay("shared link page")

        page ->
          SharedLinks.touch!(link.id, now)
          render(conn, 200, page_assigns(page, link))
      end
    else
      render(conn, 401, %{page: :phrase_prompt, link: link, error: nil})
    end
  end

  defp page_assigns({:timeline, from, to}, link),
    do: %{page: :timeline, link: link, from: from, to: to}

  defp page_assigns(page, link), do: %{page: page, link: link}

  defp render(conn, status, page) do
    html =
      conn.assigns
      |> Map.take([:locale, :rails_csrf_token, :rails_session, :base_url])
      |> Map.merge(page)
      |> SharedPages.html()
      |> IO.iodata_to_binary()

    conn =
      if status >= 400,
        do: RailsSession.put(conn, conn.private[:dawarich_rails_session_changes] || %{}),
        else: conn

    respond(conn, status, html)
  end

  defp respond(conn, 200, html) do
    conn |> Respond.rack_etag(html) |> finish(200, html)
  end

  defp respond(conn, status, html),
    do: conn |> put_resp_header("cache-control", "no-cache") |> finish(status, html)

  defp finish(conn, status, html) do
    conn
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end
end
