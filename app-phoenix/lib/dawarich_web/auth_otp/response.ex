defmodule DawarichWeb.AuthOtp.Response do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsSecret}
  alias Dawarich.Auth.{RememberCookie, SessionCookie}

  alias DawarichWeb.{
    AuthCookie,
    LayoutAssigns,
    Layouts,
    Locale,
    RailsCsrf,
    RailsHeaders,
    RequestURL
  }

  alias DawarichWeb.AuthOtp.Form

  def form(conn, pending, context \\ %{}) do
    conn = conn |> assign(:rails_session, pending) |> prepare() |> assign(:locale, "en")
    {session, _} = encoded = SessionCookie.for_form(conn.assigns.rails_session, secret(context))
    token = RailsCsrf.masked_form_token(session, "/users/otp_challenge", "POST")

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: nil,
        rails_csrf_token: token
      })

    body = Form.page(assigns)
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> headers()
    |> put_resp_content_type("text/html")
    |> send_resp(422, html)
    |> halt()
  end

  def signed_in(conn, result, context \\ %{}) do
    conn = prepare(conn)
    notice = message(conn, :signed_in_successfully)

    conn =
      AuthCookie.session(
        conn,
        SessionCookie.for_otp_login(result.session, result.user, notice, secret(context))
      )

    conn =
      if result.remember do
        expires = DateTime.add(clock(context), Accounts.remember_for())
        AuthCookie.remember(conn, RememberCookie.sign(result.remember, secret(context), expires))
      else
        conn
      end

    redirect(conn, result.session["user_return_to"] || "/")
  end

  def expired(conn, cleared, context \\ %{}) do
    conn = prepare(conn)

    flash = %{
      "discard" => [],
      "flashes" => %{"alert" => message(conn, :session_expired_please_sign_in_again)}
    }

    encoded = SessionCookie.for_form(Map.put(cleared, "flash", flash), secret(context))
    conn |> AuthCookie.session(encoded) |> redirect("/users/sign_in")
  end

  defp prepare(conn),
    do: conn |> fetch_query_params() |> Locale.call([]) |> LayoutAssigns.call([])

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()

  defp message(conn, reason) do
    {:ok, text} =
      Dawarich.I18n.t(
        conn.assigns.locale,
        "controllers.users.otp_challenge." <> Atom.to_string(reason)
      )

    text
  end

  defp redirect(conn, path) do
    conn
    |> headers()
    |> put_resp_content_type("text/html")
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> send_resp(302, "")
    |> halt()
  end

  defp headers(conn) do
    conn
    |> RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-otp")
    |> put_resp_header("cache-control", "no-cache")
  end
end
