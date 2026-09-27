defmodule DawarichWeb.RailsAuth do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Accounts, RailsCookies, RailsSecret}

  @session "_dawarich_session"
  @remember "remember_user_token"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn = fetch_cookies(conn)
    secret = Keyword.get_lazy(opts, :secret, &RailsSecret.fetch/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    session = rails_session(conn, secret, now)

    conn
    |> assign(:rails_session, session)
    |> assign(:current_user, current_user(conn, session, secret, now))
  end

  def user_id(conn) do
    case call(conn, []).assigns.current_user do
      nil -> nil
      user -> user.id
    end
  end

  def live_session(conn) do
    %{"rails_user_id" => conn.assigns[:current_user] && conn.assigns.current_user.id}
  end

  defp current_user(conn, session, secret, now) do
    case Accounts.from_session(session, now) do
      {:locked, _user} -> nil
      nil -> remembered(conn, secret, now)
      user -> user
    end
  end

  defp rails_session(conn, secret, now) do
    with true <- is_binary(secret),
         value when is_binary(value) <- conn.cookies[@session],
         {:ok, %{} = session} <- RailsCookies.decrypt(value, @session, secret, now) do
      session
    else
      _ -> %{}
    end
  end

  defp remembered(conn, secret, now) do
    with true <- is_binary(secret),
         value when is_binary(value) <- conn.cookies[@remember],
         {:ok, payload} <- RailsCookies.verify(value, @remember, secret, now) do
      Accounts.from_remember_cookie(payload, now)
    else
      _ -> nil
    end
  end
end
