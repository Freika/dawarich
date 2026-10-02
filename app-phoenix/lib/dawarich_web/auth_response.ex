defmodule DawarichWeb.AuthResponse do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsSecret}
  alias Dawarich.Auth.{RememberCookie, SessionCookie}
  alias DawarichWeb.{AuthCookie, AuthForm, AuthMessages, RailsCsrf, RequestURL}

  def signed_in(conn, user, remember) do
    session = conn.assigns.rails_session

    conn =
      AuthCookie.session(
        conn,
        SessionCookie.for_login(
          session,
          user,
          AuthMessages.notice(conn, "devise.sessions.signed_in"),
          RailsSecret.fetch()
        )
      )

    conn =
      if remember,
        do:
          AuthCookie.remember(
            conn,
            RememberCookie.sign(
              remember,
              RailsSecret.fetch(),
              DateTime.add(DateTime.utc_now(), Accounts.remember_for())
            )
          ),
        else: conn

    redirect(conn, return_to(session))
  end

  def signed_out(conn) do
    conn
    |> AuthCookie.session(
      SessionCookie.for_logout(
        AuthMessages.notice(conn, "devise.sessions.signed_out"),
        RailsSecret.fetch()
      )
    )
    |> AuthCookie.forget()
    |> redirect("/")
  end

  def form(conn, email, error, status) do
    conn =
      conn
      |> fetch_query_params()
      |> DawarichWeb.Locale.call([])
      |> DawarichWeb.LayoutAssigns.call([])

    {session, _} =
      encoded = SessionCookie.for_form(conn.assigns.rails_session, RailsSecret.fetch())

    token = RailsCsrf.masked_token(session)

    body =
      AuthForm.render(token, email, error,
        locale: conn.assigns.locale,
        registration_enabled: conn.private[:auth_registration_enabled]
      )

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: nil,
        rails_csrf_token: token,
        inner_content: Phoenix.HTML.raw(body)
      })

    app = DawarichWeb.Layouts.app(assigns)

    html =
      DawarichWeb.Layouts.root(%{assigns | inner_content: app}) |> Phoenix.HTML.Safe.to_iodata()

    conn = conn |> AuthCookie.session(encoded) |> DawarichWeb.RailsHeaders.call([])

    conn =
      if status == 200,
        do: put_resp_header(conn, "x-dawarich-auth-owner", "native-credentials"),
        else: conn

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  defp redirect(conn, path) do
    conn
    |> DawarichWeb.RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-credentials")
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> send_resp(303, "")
    |> halt()
  end

  defp return_to(%{"user_return_to" => "/" <> rest = path}) do
    if String.starts_with?(rest, "/") or String.contains?(path, ["\\", "\t", "\r", "\n"]),
      do: "/",
      else: path
  end

  defp return_to(_), do: "/"
end
