defmodule DawarichWeb.SharedLinkCookie do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret, UserTimeZone}
  alias DawarichWeb.RackScheme

  @thirty_days "SELECT ($1::timestamptz AT TIME ZONE z.name + interval '30 days') AT TIME ZONE z.name FROM z"
  @anonymous %{"timezone" => ""}

  defdelegate proof_identity(token), to: Dawarich.Sharing.UnlockToken

  def proofs(conn, now \\ DateTime.utc_now(), secret \\ RailsSecret.fetch()) do
    fetch_cookies(conn).req_cookies
    |> Enum.filter(fn {name, _} -> String.starts_with?(name, "shared_link_") end)
    |> Enum.take(32)
    |> Enum.reduce(%{}, fn {name, value}, acc ->
      id = String.replace_prefix(name, "shared_link_", "")

      with true <- Dawarich.SharedLinks.canonical?(id),
           {:ok, token, expiry} when is_binary(token) <-
             RailsCookies.decrypt_metadata(value, name, secret, now) do
        Map.put(acc, id, %{"identity" => proof_identity(token), "expires_at" => expiry})
      else
        _ -> acc
      end
    end)
  end

  defdelegate unlock_token(id, phrase), to: Dawarich.Sharing.UnlockToken

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
