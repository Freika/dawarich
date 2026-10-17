defmodule DawarichWeb.Api.HexagonsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.MapApi.{Hexagons, Fog}
  alias DawarichWeb.Api.Respond
  alias Dawarich.Sharing.Delivery
  def init(action), do: action

  def call(conn, action) do
    uuid = conn.assigns.api_params["uuid"]

    target =
      if is_binary(uuid) and uuid != "" and action != :fog do
        viewer = conn.assigns[:api_user]

        zone =
          case viewer do
            %{timezone: name} -> Dawarich.RailsTimeZone.name(%{"timezone" => name})
            _ -> Dawarich.RailsTimeZone.name(%{"timezone" => ""})
          end

        {:month, uuid, zone}
      end

    admitted =
      if target, do: Delivery.admit(target, Delivery.now(clock: conn.private[:dawarich_clock]))

    result =
      case action do
        :index -> Hexagons.fetch(conn.assigns[:api_user], conn.assigns.api_params)
        :bounds -> Hexagons.bounds(conn.assigns[:api_user], conn.assigns.api_params)
        :fog -> apply(Fog, :fetch, [conn.assigns.api_user, conn.assigns.api_params])
      end

    conn =
      if not is_nil(target) and match?({:ok, _}, result),
        do:
          DawarichWeb.PublicDelivery.api(
            conn,
            target,
            admitted,
            "Shared stats not found or no longer available"
          ),
        else: conn

    case result do
      {:ok, body} -> Respond.json(conn, 200, body)
      {:error, status, body} when is_map(body) -> Respond.json(conn, status, body)
      {:error, status, message} -> Respond.json(conn, status, {:object, [{"error", message}]})
      _ -> Respond.json(conn, 500, {:object, [{"error", "Failed to generate hexagon grid"}]})
    end
  end
end
