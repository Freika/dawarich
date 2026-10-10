defmodule DawarichWeb.OperatorGrant do
  @moduledoc false

  import Plug.Conn
  alias DawarichWeb.RailsAuth

  def issue(conn) do
    grant = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    login = login(conn)

    with true <- is_binary(login),
         {:ok, "OK"} <-
           Dawarich.Admin.OperatorGrant.store(conn.assigns.current_user, login, grant) do
      put_session(conn, "operator_grant", grant)
    else
      _ -> conn |> send_resp(503, "") |> halt()
    end
  end

  def authorized?(user, context), do: Dawarich.Admin.OperatorGrant.authorized?(user, context)

  def login(%{private: %{dawarich_rails_user: _user}} = conn) do
    session = conn.assigns.rails_session

    identity =
      session["session_id"] || session["_csrf_token"] ||
        conn.cookies["_dawarich_session"] || conn.cookies["remember_user_token"]

    if conn.assigns.current_user && is_binary(identity) do
      digest({conn.assigns.current_user.id, identity})
    end
  end

  def login(conn), do: conn |> RailsAuth.call([]) |> login()

  defp digest(value), do: Dawarich.Admin.OperatorGrant.digest(value)
end
