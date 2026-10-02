defmodule DawarichWeb.SharedLinkCookie do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret, UserTimeZone}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RackScheme

  @thirty_days "SELECT ($1::timestamptz AT TIME ZONE z.name + interval '30 days') AT TIME ZONE z.name FROM z"
  @anonymous %{"timezone" => ""}

  def unlock_token(id, phrase) do
    unless Ruby.blank?(phrase),
      do: :sha256 |> :crypto.hash("#{id}:#{phrase}") |> Base.encode16(case: :lower)
  end

  def expires_at(link, now, settings, env \\ System.get_env())

  def expires_at(%{expires_at: nil}, %DateTime{} = now, settings, env) do
    %{rows: [[at]]} = UserTimeZone.query!(@thirty_days, [now], settings || @anonymous, env)
    at
  end

  def expires_at(%{expires_at: %DateTime{} = at}, _now, _settings, _env), do: at

  def expires_at(%{expires_at: %NaiveDateTime{} = at}, _now, _settings, _env),
    do: DateTime.from_naive!(at, "Etc/UTC")

  def put(
        conn,
        %{id: id, magic_phrase: phrase},
        %DateTime{} = at,
        secret \\ RailsSecret.fetch()
      ) do
    name = "shared_link_#{id}"

    put_resp_cookie(conn, name, RailsCookies.encrypt(unlock_token(id, phrase), name, secret, at),
      path: "/",
      http_only: true,
      same_site: "Lax",
      secure: RackScheme.ssl?(conn),
      extra: "expires=" <> Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S GMT")
    )
  end

  def unlocked?(
        conn,
        %{id: id, magic_phrase: phrase},
        %DateTime{} = now,
        secret \\ RailsSecret.fetch()
      ) do
    name = "shared_link_#{id}"

    case unlock_token(id, phrase) do
      nil ->
        true

      token ->
        with value when is_binary(value) <- fetch_cookies(conn).req_cookies[name],
             {:ok, cookie} when is_binary(cookie) <-
               RailsCookies.decrypt(value, name, secret, now) do
          Plug.Crypto.secure_compare(cookie, token)
        else
          _ -> false
        end
    end
  end
end
