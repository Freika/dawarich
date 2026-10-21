defmodule DawarichWeb.Api.StandaloneMap do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.StandaloneError

  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()
  def init(action), do: action

  def call(conn, :settings), do: DawarichWeb.Api.SettingsController.call(conn, :index)

  def call(conn, :progress) do
    conn = DawarichWeb.Api.Auth.admit(conn, conn.assigns.api_user, [])
    if conn.halted, do: conn, else: handle(conn, :progress)
  end

  def call(conn, action), do: handle(conn, action)

  defp handle(conn, action) do
    if Dawarich.ReleaseMigration.self_hosted?() do
      case Dawarich.RailsTime.with_zone(conn.assigns.api_user.timezone, fn ->
             run(conn, action, Map.merge(conn.assigns.api_params, conn.path_params))
           end) do
        %Plug.Conn{} = result -> result
        _ -> StandaloneError.respond(conn, "standalone_map_timezone", 422)
      end
    else
      StandaloneError.respond(conn, "standalone_map_cloud")
    end
  rescue
    _ -> StandaloneError.respond(conn, "standalone_map_failure", 500)
  end

  defp run(conn, :progress, _params) do
    json(conn, 200, Dawarich.Transportation.RecalculationStatus.data(conn.assigns.api_user.id))
  end

  defp json(conn, status, term),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(term))
      |> halt()
end
