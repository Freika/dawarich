defmodule Dawarich.Auth.Apple.Cookies do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{RailsCookies, RailsSecret}

  def put(conn, key, value, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    wire = RailsCookies.encrypt(value, key, secret, DateTime.add(now, 600))

    put_resp_cookie(conn, key, wire,
      path: "/",
      http_only: true,
      same_site: "None",
      secure: true,
      max_age: 600
    )
  end

  def take(conn, context) do
    conn = fetch_cookies(conn)

    values =
      Map.new(~w(apple_oauth_nonce apple_oauth_state apple_pending_import_ticket), fn key ->
        {key, read(conn.cookies[key], key, context)}
      end)

    conn = Enum.reduce(Map.keys(values), conn, &delete_resp_cookie(&2, &1, path: "/"))
    session = conn.assigns[:rails_session] || %{}

    session =
      if values["apple_pending_import_ticket"],
        do: Map.put_new(session, "pending_import_ticket", values["apple_pending_import_ticket"]),
        else: session

    {assign(conn, :rails_session, session), values}
  end

  defp read(nil, _, _), do: nil

  defp read(value, key, context) do
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    case RailsCookies.decrypt(value, key, secret, now) do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end
end
