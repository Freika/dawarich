defmodule DawarichWeb.SharedLinkPage do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.Sharing.Delivery
  alias Dawarich.SharedLinks
  alias Dawarich.SharedLinks.FamilyAudience
  alias DawarichWeb.{LayoutAssigns, RailsSession, RequestURL, SharedLinkCookie, SharedPages}
  alias DawarichWeb.Api.Respond

  @incorrect "controllers.shared.links.incorrect_phrase"

  @impl true
  def init(action), do: action

  @impl true
  def call(%{path_params: %{"id" => id}} = conn, :show) do
    now = DateTime.utc_now()
    conn = DawarichWeb.PublicShareAuth.prepare(conn)

    case if(SharedLinks.canonical?(id), do: SharedLinks.active(id, now)) do
      nil ->
        render(conn, 404, %{page: :not_found})

      link ->
        if FamilyAudience.accessible?(link, conn.assigns[:current_user], now),
          do: show(audience(conn, link), link, now),
          else: render(conn, 404, %{page: :not_found})
    end
  end

  def call(%{path_params: %{"id" => id}} = conn, :unlock) do
    now = DateTime.utc_now()
    phrase = conn.assigns.api_params["phrase"] || ""

    case if(SharedLinks.canonical?(id), do: SharedLinks.active(id, now)) do
      nil ->
        conn |> LayoutAssigns.call([]) |> render(404, %{page: :not_found})

      link ->
        if not FamilyAudience.accessible?(link, conn.assigns[:current_user], now) do
          conn |> LayoutAssigns.call([]) |> render(404, %{page: :not_found})
        else
          unlock(audience(conn, link), link, id, phrase, now)
        end
    end
  end

  defp audience(conn, link), do: assign(conn, :family_share, FamilyAudience.family_only?(link))

  defp unlock(conn, link, id, phrase, now) do
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

  defp show(conn, link, now) do
    if SharedLinkCookie.unlocked?(conn, link, now) do
      with {:ok, conn, token, grant} <- DawarichWeb.PublicShareAuth.issue(conn, link, now),
           {:ok, page} <- Dawarich.Sharing.Public.read(grant, now) do
        SharedLinks.touch!(link.id, now)

        allowed = fn current, clock ->
          FamilyAudience.accessible?(
            current,
            DawarichWeb.RailsAuth.delivery_user(conn, clock),
            clock
          ) and
            SharedLinkCookie.unlocked?(conn, current, clock)
        end

        target = {:link, link, allowed}

        admitted =
          Delivery.admit(target, now,
            before_admission: conn.private[:dawarich_before_admission] || fn -> :ok end
          )

        conn = put_private(conn, :public_delivery, {target, admitted})

        content =
          Phoenix.Component.live_render(conn, DawarichWeb.PublicShareLive,
            session: %{"bootstrap" => token, "locale" => conn.assigns.locale}
          )

        render(assign(conn, :live_module, DawarichWeb.PublicShareLive), 200, %{
          page: :native,
          link: page.link,
          public_native_html: content
        })
      else
        _ -> render(conn, 404, %{page: :not_found})
      end
    else
      render(conn, 401, %{page: :phrase_prompt, link: link, error: nil})
    end
  end

  defp render(conn, status, page) do
    assigns =
      if conn.assigns[:family_share] do
        navbar =
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )

        Map.merge(conn.assigns, %{
          navbar: navbar,
          page_title: nil,
          flash: %{},
          rails_js: true,
          rails_charts: false
        })
      else
        conn.assigns
      end

    html =
      assigns
      |> Map.merge(page)
      |> SharedPages.html()
      |> IO.iodata_to_binary()

    conn =
      if status >= 400,
        do: RailsSession.put(conn, conn.private[:dawarich_rails_session_changes] || %{}),
        else: conn

    if status == 200 do
      {target, admitted} = conn.private.public_delivery

      case Delivery.deliver(target, admitted, html,
             clock: conn.private[:dawarich_clock],
             after_read: conn.private[:dawarich_before_delivery] || fn -> :ok end
           ) do
        {:ok, html} -> respond(conn, status, html)
        _ -> render(conn, 404, %{page: :not_found})
      end
    else
      respond(conn, status, html)
    end
  end

  defp respond(conn, 200, html) do
    conn
    |> Respond.rack_etag(html, cache_control(conn, "max-age=0, private, must-revalidate"))
    |> finish(200, html)
  end

  defp respond(conn, status, html),
    do:
      conn
      |> put_resp_header("cache-control", cache_control(conn, "no-cache"))
      |> finish(status, html)

  defp cache_control(conn, public),
    do: if(conn.assigns[:family_share], do: "private, no-store", else: public)

  defp finish(conn, status, html) do
    conn
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end
end
