defmodule DawarichWeb.RouteVideoRequestGate do
  @moduledoc false

  def actions?(conn, _params),
    do:
      query?(conn) and
        (Dawarich.Standalone.enabled?() or DawarichWeb.LayoutAssigns.self_hosted?())

  defp query?(%{method: "POST", path_info: ["route_videos", _id]} = conn) do
    conn.query_string == "" or
      DawarichWeb.A8FormDecode.urlencoded(conn.query_string) == %{"_method" => "delete"}
  rescue
    _ -> false
  end

  defp query?(conn), do: conn.query_string == ""
end
