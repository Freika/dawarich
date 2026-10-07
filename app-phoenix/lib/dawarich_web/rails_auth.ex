defmodule DawarichWeb.RailsAuth do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Accounts, RailsCookies, RailsSecret}

  @session "_dawarich_session"
  @remember "remember_user_token"
  @layout ~w(notification_session locale suggested_locale self_hosted request_path query_params flash_messages rails_csrf_token base_url)a

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn = fetch_cookies(conn)
    secret = Keyword.get_lazy(opts, :secret, &RailsSecret.fetch/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    session = rails_session(conn, secret, now)
    {user, locked} = current_user(conn, session, secret, now)

    conn
    |> assign(:rails_session, session)
    |> assign(:current_user, user)
    |> assign(:rails_locked, locked)
    |> put_private(:dawarich_rails_user, user)
  end

  def session_user(conn, opts \\ []) do
    conn = fetch_cookies(conn)
    secret = Keyword.get_lazy(opts, :secret, &RailsSecret.fetch/0)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    Accounts.from_session(rails_session(conn, secret, now), now)
  end

  def user_id(conn) do
    user =
      case Map.fetch(conn.private, :dawarich_rails_user) do
        {:ok, user} -> user
        :error -> call(conn, []).assigns.current_user
      end

    user && user.id
  end

  def live_session(conn) do
    Map.new(
      [
        {"rails_user_id", conn.assigns[:current_user] && conn.assigns.current_user.id},
        {"notification_session",
         DawarichWeb.NotificationSession.topic(conn.assigns[:rails_session] || %{})}
      ] ++
        for(
          key <- @layout -- [:notification_session],
          do: {Atom.to_string(key), conn.assigns[key]}
        )
    )
  end

  defp current_user(conn, session, secret, now) do
    if Dawarich.Standalone.enabled?() and
         match?({:ok, _, _}, Dawarich.Auth.Otp.Pending.valid(session, DateTime.to_unix(now))) do
      {nil, nil}
    else
      case Accounts.from_session(session, now) do
        {:locked, _user} -> {nil, :session}
        nil -> conn |> remembered(secret, now) |> remembered_user()
        user -> {user, nil}
      end
    end
  end

  defp remembered_user({:locked, _user}), do: {nil, :cookie}
  defp remembered_user(user), do: {user, nil}

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
