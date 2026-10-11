defmodule DawarichWeb.OnboardingQr do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      register_before_send(conn, fn response ->
        response
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("vary", "Cookie")
        |> put_resp_header("x-content-type-options", "nosniff")
      end)

    cond do
      conn.method not in ["GET", "HEAD"] -> refuse(conn, 405)
      cross_site?(conn) -> refuse(conn, 403)
      true -> serve(DawarichWeb.RailsAuth.call(conn, []))
    end
  rescue
    _ -> refuse(conn, 503)
  end

  defp serve(%{assigns: %{current_user: %{} = user}} = conn) do
    scope = Dawarich.Maps.principal(user, conn.assigns[:locale] || "en")

    case Dawarich.Onboarding.qr_svg(scope, DawarichWeb.RequestURL.base(conn)) do
      {:ok, svg} ->
        conn
        |> assign(:current_user, nil)
        |> put_resp_content_type("image/svg+xml", nil)
        |> send_resp(200, svg)
        |> halt()

      _ ->
        refuse(conn, 401)
    end
  end

  defp serve(conn), do: refuse(conn, 401)

  defp refuse(conn, status), do: conn |> send_resp(status, "") |> halt()

  defp cross_site?(conn),
    do: get_req_header(conn, "sec-fetch-site") not in [[], ["same-origin"], ["none"]]
end
