defmodule DawarichWeb.AuthApple.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Auth.Apple.{Request, Callback}

  def init(opts), do: opts
  def route?(conn), do: conn.request_path in ["/users/auth/apple", "/users/auth/apple/callback"]

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and route?(conn) do
      context = Keyword.get(opts, :context, %{})
      env = Map.get_lazy(context, :env, &System.get_env/0)

      context =
        context
        |> Map.put_new(:self_hosted, Dawarich.ReleaseMigration.self_hosted?(env))
        |> Map.put_new(:base_url, DawarichWeb.RequestURL.base(conn))
        |> Map.put_new(:ip, conn.remote_ip |> :inet.ntoa() |> to_string())

      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])

      cond do
        conn.halted -> conn
        not Request.enabled?(context) -> conn |> send_resp(404, "") |> halt()
        true -> handle(conn, context)
      end
    else
      conn
    end
  rescue
    _ -> conn |> send_resp(503, "Authentication unavailable") |> halt()
  end

  defp handle(conn, context) do
    conn =
      if conn.assigns[:rails_session],
        do: conn,
        else:
          DawarichWeb.RailsAuth.call(conn,
            now: fn -> Map.get(context, :clock, &DateTime.utc_now/0).() end
          )

    case {conn.method, conn.request_path} do
      {"GET", "/users/auth/apple"} ->
        Request.call(conn, context)

      {"POST", "/users/auth/apple/callback"} ->
        case DawarichWeb.AuthApi.Input.native(conn) do
          {:ok, params, conn} -> Callback.call(conn, params, context)
          {:error, conn} -> conn |> send_resp(400, "Invalid Apple request") |> halt()
        end

      _ ->
        conn |> send_resp(404, "") |> halt()
    end
  end
end
