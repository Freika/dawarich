defmodule DawarichWeb.AuthTwoFactor.Response do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, Navbar, RailsSecret}
  alias Dawarich.Auth.SessionCookie

  alias DawarichWeb.{
    AuthCookie,
    LayoutAssigns,
    Layouts,
    Locale,
    RailsCsrf,
    RailsHeaders,
    RequestURL
  }

  alias DawarichWeb.AuthTwoFactor.Form

  def form(conn, actor, render, status, context \\ %{}) do
    user = Accounts.get(actor.id)
    conn = prepare(conn, user)
    {session, _} = encoded = SessionCookie.for_form(conn.assigns.rails_session, secret(context))

    flashes =
      if render[:reason],
        do:
          List.keystore(
            conn.assigns.flash_messages,
            "alert",
            0,
            {"alert", message(conn, render.reason)}
          ),
        else: conn.assigns.flash_messages

    conn = assign(conn, :flash_messages, flashes)

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        rails_csrf_token: RailsCsrf.masked_token(session),
        page_title: Form.title(render.kind, conn.assigns.locale),
        kind: render.kind,
        enabled: render.user.otp_required_for_login,
        admin: user.admin,
        two_factor: true,
        secret: render[:secret],
        uri: render[:uri],
        codes: render[:codes] || [],
        navbar: Navbar.load(user, now: conn.assigns.now, self_hosted: conn.assigns.self_hosted)
      })

    body = Form.page(assigns)
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> headers(flashes != [])
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  def redirect(conn, reason, context \\ %{}) do
    conn = prepare(conn, conn.assigns.current_user)
    type = if reason == :two_factor_authentication_disabled, do: "notice", else: "alert"
    flash = %{"discard" => [], "flashes" => %{type => message(conn, reason)}}
    session = Map.put(conn.assigns.rails_session, "flash", flash)

    path =
      if reason == :two_factor_authentication_is_not_configured_on_this_instance,
        do: "/settings/general",
        else: "/settings/two_factor"

    conn
    |> AuthCookie.session(SessionCookie.for_form(session, secret(context)))
    |> headers(true)
    |> put_resp_content_type("text/html")
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> send_resp(302, "")
    |> halt()
  end

  defp prepare(conn, user) do
    conn
    |> assign(:current_user, user)
    |> put_private(:dawarich_rails_user, user)
    |> fetch_query_params()
    |> Locale.call([])
    |> LayoutAssigns.call([])
  end

  defp message(conn, reason) do
    {:ok, text} =
      Dawarich.I18n.t(
        conn.assigns.locale,
        "controllers.settings.two_factor." <> Atom.to_string(reason)
      )

    text
  end

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)

  defp headers(conn, flash?) do
    conn
    |> RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-two-factor")
    |> put_resp_header(
      "cache-control",
      if(flash?, do: "no-cache", else: "max-age=0, private, must-revalidate")
    )
  end
end
