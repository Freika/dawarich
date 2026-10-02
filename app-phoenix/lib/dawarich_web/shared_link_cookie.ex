defmodule DawarichWeb.SharedLinkCookie do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret, Repo, TimeZoneName}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RackScheme

  def unlock_token(id, phrase) do
    unless Ruby.blank?(phrase),
      do: :sha256 |> :crypto.hash("#{id}:#{phrase}") |> Base.encode16(case: :lower)
  end

  def put(
        conn,
        %{id: id, magic_phrase: phrase, expires_at: expires_at},
        %DateTime{} = now,
        secret \\ RailsSecret.fetch()
      ) do
    at = utc(expires_at) || thirty_days_from(now)
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

  defp thirty_days_from(now) do
    zone = TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))

    %{rows: [[at]]} =
      Repo.query!(
        "SELECT ($1::timestamptz AT TIME ZONE $2 + interval '30 days') AT TIME ZONE $2",
        [now, zone]
      )

    at
  end

  defp utc(nil), do: nil
  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
