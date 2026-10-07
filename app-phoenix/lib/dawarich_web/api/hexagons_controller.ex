defmodule DawarichWeb.Api.HexagonsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.MapApi.{Hexagons, Fog}
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, action) do
    result =
      case action do
        :index -> Hexagons.fetch(conn.assigns[:api_user], conn.assigns.api_params)
        :bounds -> Hexagons.bounds(conn.assigns[:api_user], conn.assigns.api_params)
        :fog -> apply(Fog, :fetch, [conn.assigns.api_user, conn.assigns.api_params])
      end

    case result do
      {:ok, body} -> Respond.json(conn, 200, body)
      {:error, status, body} when is_map(body) -> Respond.json(conn, status, body)
      {:error, status, message} -> Respond.json(conn, status, {:object, [{"error", message}]})
      _ -> Respond.json(conn, 500, {:object, [{"error", "Failed to generate hexagon grid"}]})
    end
  end
end
