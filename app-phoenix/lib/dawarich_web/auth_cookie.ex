defmodule DawarichWeb.AuthCookie do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.ForceSSL

  def session(conn, {session, value}) do
    conn = fetch_cookies(conn)

    conn = %{
      conn
      | cookies: Map.put(conn.cookies, "_dawarich_session", value),
        req_cookies: Map.put(conn.req_cookies, "_dawarich_session", value)
    }

    conn
    |> assign(:rails_session, session)
    |> put_private(:dawarich_rails_session_changes, %{})
    |> put_resp_cookie("_dawarich_session", value, options())
  end

  def remember(conn, value) do
    put_resp_cookie(
      conn,
      "remember_user_token",
      value,
      options() ++ [max_age: Dawarich.Accounts.remember_for()]
    )
  end

  def forget(conn), do: delete_resp_cookie(conn, "remember_user_token", options())

  defp options do
    [path: "/", http_only: true, same_site: "Lax", secure: ForceSSL.enabled?()]
  end
end
