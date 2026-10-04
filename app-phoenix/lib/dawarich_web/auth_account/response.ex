defmodule DawarichWeb.AuthAccount.Response do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, Navbar, RailsSecret}
  alias Dawarich.Auth.SessionCookie

  alias DawarichWeb.{
    AuthCookie,
    AuthMessages,
    LayoutAssigns,
    Layouts,
    Locale,
    RailsCsrf,
    RailsHeaders,
    RequestURL
  }

  def updated(conn, user, context \\ %{}) do
    user = %{
      conn.assigns.current_user
      | email: user.email,
        encrypted_password: user.encrypted_password
    }

    conn = current(conn, user)

    conn
    |> AuthCookie.session(
      SessionCookie.for_account_update(
        conn.assigns.rails_session,
        user,
        AuthMessages.notice(conn, "devise.registrations.updated"),
        secret(context)
      )
    )
    |> headers()
    |> put_resp_header("location", RequestURL.base(conn) <> "/")
    |> send_resp(303, "")
    |> halt()
  end

  def form(conn, actor, render, context \\ %{}) do
    user = Accounts.get(actor.id)

    conn =
      conn |> current(user) |> fetch_query_params() |> Locale.call([]) |> LayoutAssigns.call([])

    {session, _} = encoded = SessionCookie.for_form(conn.assigns.rails_session, secret(context))
    token = RailsCsrf.masked_token(session)

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        rails_csrf_token: token,
        account_errors: render.errors,
        account_email: render.email,
        navbar: Navbar.load(user, now: conn.assigns.now, self_hosted: conn.assigns.self_hosted)
      })

    assigns = Map.merge(assigns, DawarichWeb.AccountLive.Edit.page(user, %{}, assigns))
    body = DawarichWeb.AccountLive.Edit.render(assigns)
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> headers()
    |> put_resp_content_type("text/html")
    |> send_resp(422, html)
    |> halt()
  end

  defp current(conn, user),
    do: conn |> assign(:current_user, user) |> put_private(:dawarich_rails_user, user)

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)

  defp headers(conn),
    do:
      conn |> RailsHeaders.call([]) |> put_resp_header("x-dawarich-auth-owner", "native-account")
end
