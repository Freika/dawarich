defmodule DawarichWeb.BrowserMapAuth do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.Api.{Auth, Respond}

  def init(opts), do: opts

  def call(conn, _) do
    conn =
      conn
      |> Respond.prepare()
      |> put_private(:dawarich_native_api, true)
      |> put_private(:dawarich_browser_map, true)

    cond do
      conn.method not in ["GET", "HEAD"] ->
        Respond.json(conn, 405, %{error: "read_only"})

      not same_origin?(conn) ->
        Respond.json(conn, 403, %{error: "origin_refused"})

      Map.has_key?(conn.query_params, "api_key") ->
        Respond.json(conn, 400, %{error: "credential_refused"})

      true ->
        authenticate(conn)
    end
  rescue
    _ -> conn |> Respond.prepare() |> Respond.json(503, %{error: "read_unavailable"})
  end

  defp authenticate(conn) do
    conn = DawarichWeb.RailsAuth.call(conn, [])
    user = conn.assigns.current_user
    actor = user && api_user(user)

    conn =
      conn
      |> assign(:current_user, nil)
      |> assign(:rails_session, %{})
      |> put_private(:dawarich_rails_user, nil)
      |> assign(:api_params, conn.query_params)
      |> assign(:api_tag, "browser_map")
      |> register_before_send(fn response ->
        response
        |> put_resp_header("vary", "Cookie")
        |> put_resp_header("cache-control", "private, no-store")
      end)

    Auth.admit(conn, actor, require_active: false)
  end

  defp api_user(user) do
    user
    |> Map.take(~w(id email status plan subscription_source)a)
    |> Map.put(:active_until, user.active_until && DateTime.to_naive(user.active_until))
    |> Map.put(:timezone, Dawarich.UserTimeZone.name(Dawarich.UserSettings.get(user)))
    |> Map.put(:settings, %{
      "timezone" => Dawarich.UserTimeZone.name(Dawarich.UserSettings.get(user))
    })
  end

  defp same_origin?(conn) do
    site = get_req_header(conn, "sec-fetch-site")
    origin = get_req_header(conn, "origin")

    site in [[], ["same-origin"], ["none"]] and
      (origin == [] or
         origin == [
           URI.to_string(%URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port})
         ])
  end
end
