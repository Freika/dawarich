defmodule DawarichWeb.OperatorGrant do
  @moduledoc false

  import Plug.Conn
  alias DawarichWeb.{OperatorRedirect, RailsAuth}

  @prefix "dawarich:operator_grant:"
  @ttl 3600

  def issue(conn) do
    grant = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    login = login(conn)

    with true <- is_binary(login),
         {:ok, "OK"} <-
           Dawarich.Redis.cache_command([
             "SET",
             @prefix <> grant,
             binding(conn.assigns.current_user, login),
             "EX",
             Integer.to_string(@ttl)
           ]) do
      put_session(conn, "operator_grant", grant)
    else
      _ -> conn |> send_resp(503, "") |> halt()
    end
  end

  def authorized?(user, %{"operator_grant" => grant, "operator_login" => login})
      when is_binary(grant) and byte_size(grant) == 43 and is_binary(login) do
    with true <- OperatorRedirect.operator?(user),
         {:ok, value} when is_binary(value) <-
           Dawarich.Redis.cache_command(["GET", @prefix <> grant]) do
      Plug.Crypto.secure_compare(value, binding(user, login))
    else
      _ -> false
    end
  end

  def authorized?(_user, _context), do: false

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

  defp binding(user, login),
    do:
      digest(
        {user.id, login, System.get_env("SIDEKIQ_USERNAME"), System.get_env("SIDEKIQ_PASSWORD")}
      )

  defp digest(value),
    do:
      :crypto.mac(:hmac, :sha256, Dawarich.RailsSecret.fetch(), :erlang.term_to_binary(value))
      |> Base.url_encode64(padding: false)
end
