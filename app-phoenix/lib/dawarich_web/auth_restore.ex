defmodule DawarichWeb.AuthRestore do
  @moduledoc "Remember restoration hook; call after RailsAuth and before layout/session staging."
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret}
  alias Dawarich.Auth.{Admission, Credentials, SessionCookie}
  alias DawarichWeb.AuthCookie

  def call(conn, opts) do
    now = DateTime.utc_now()
    session = conn.assigns.rails_session

    if (Keyword.get(opts, :enabled, false) and
          (Keyword.get(opts, :native, false) or
             Admission.context(
               session,
               conn.req_headers,
               false,
               System.get_env("SELF_HOSTED") == "true"
             ) == :ok) and conn.assigns.current_user) &&
         is_nil(Accounts.from_session(session, now)) do
      restore(conn, session, now)
    else
      conn
    end
  end

  defp restore(conn, session, now) do
    secret = RailsSecret.fetch()

    with cookie when is_binary(cookie) <- conn.cookies["remember_user_token"],
         {:ok, payload} <- RailsCookies.verify(cookie, "remember_user_token", secret, now),
         {:ok, %{user: user}} <-
           Credentials.restore(payload, %{ip: DawarichWeb.RailsRemoteIp.ip(conn)}) do
      conn
      |> AuthCookie.session(SessionCookie.for_restore(session, user, secret))
      |> register_before_send(
        &put_resp_header(&1, "x-dawarich-auth-restore", "native-credentials")
      )
    else
      _ -> conn |> assign(:current_user, nil) |> put_private(:dawarich_rails_user, nil)
    end
  end
end
