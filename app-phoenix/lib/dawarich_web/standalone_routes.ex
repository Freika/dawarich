defmodule DawarichWeb.StandaloneRoutes do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.Api

  @routes %{
    {"POST", "/api/v1/recalculations"} => {Api.RecalculationsController, :create, true},
    {"GET", "/api/v1/settings/mobile"} => {Api.MobileSettingsController, :show, false},
    {"PATCH", "/api/v1/settings/mobile"} => {Api.MobileSettingsController, :update, true},
    {"GET", "/api/v1/areas"} => {Api.AreasController, :index, false},
    {"POST", "/api/v1/areas"} => {Api.AreasController, :create, false},
    {"PATCH", "/api/v1/settings"} => {Api.SettingsController, :update, true},
    {"GET", "/api/v1/timeline"} => {Api.TimelineController, :index, false},
    {"GET", "/api/v1/maps/hexagons"} => {Api.HexagonsController, :index, false}
  }
  @admission [
    DawarichWeb.HostAuthorization,
    DawarichWeb.ForceSSL,
    DawarichWeb.RateLimit,
    Api.Body
  ]

  def dispatch(conn) do
    case route(conn) do
      nil ->
        conn

      {handler, action, active, params} ->
        conn = conn |> assign(:api_tag, "api") |> Map.put(:path_params, params)

        conn =
          if handler == Api.RecalculationsController,
            do: put_private(conn, :dawarich_native_api, true),
            else: conn

        conn = Enum.reduce_while(@admission, conn, &admit/2)
        conn = if conn.halted, do: conn, else: authenticate(conn, active)

        if conn.halted do
          conn
        else
          conn = actor_settings(conn)
          conn |> handler.call(action) |> halt()
        end
    end
  end

  defp route(%{method: "PATCH", path_info: ["api", "v1", "points", id, "position"]}) do
    if id =~ ~r/\A\d{1,18}\z/,
      do: {Api.PointPositionsController, :update, true, %{"point_id" => id}}
  end

  defp route(%{method: method, path_info: ["api", "v1", "areas", id]})
       when method in ["GET", "PATCH", "PUT"] do
    action = if method == "GET", do: :show, else: :update
    {Api.AreasController, action, false, %{"id" => id}}
  end

  defp route(conn) do
    case @routes[{conn.method, conn.request_path}] do
      {handler, action, active} -> {handler, action, active, %{}}
      nil -> nil
    end
  end

  defp admit(module, conn) do
    conn = module.call(conn, module.init([]))
    if conn.halted, do: {:halt, conn}, else: {:cont, conn}
  end

  defp authenticate(conn, active) do
    if conn.request_path == "/api/v1/maps/hexagons" and
         Dawarich.Tiles.Http.present?(conn.assigns.api_params["uuid"]),
       do: Api.Auth.public(conn),
       else: Api.Auth.call(conn, require_active: active)
  end

  defp actor_settings(%{assigns: %{api_user: nil}} = conn), do: conn

  defp actor_settings(conn) do
    user = conn.assigns.api_user
    assign(conn, :api_user, Map.put(user, :settings, Dawarich.Accounts.settings(user.id)))
  end
end
