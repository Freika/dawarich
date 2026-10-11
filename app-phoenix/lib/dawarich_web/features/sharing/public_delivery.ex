defmodule DawarichWeb.PublicDelivery do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Sharing.Delivery

  def api(conn, target, admitted, message) do
    register_before_send(conn, fn conn ->
      if conn.status in 200..299 or conn.status == 304 do
        case Delivery.deliver(target, admitted, conn.resp_body,
               clock: conn.private[:dawarich_clock],
               after_read: conn.private[:dawarich_before_delivery] || fn -> :ok end
             ) do
          {:ok, _} ->
            conn

          _ ->
            conn
            |> delete_resp_header("etag")
            |> put_resp_header("cache-control", "no-cache")
            |> put_resp_content_type("application/json")
            |> Map.put(:status, 404)
            |> Map.put(:resp_body, DawarichWeb.Api.Respond.encode(%{"error" => message}))
        end
      else
        conn
      end
    end)
  end
end
