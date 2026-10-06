defmodule DawarichWeb.RouteVideoRequestGate do
  @moduledoc false

  def actions?(conn, _params),
    do:
      query?(conn) and
        (Dawarich.Standalone.enabled?() or DawarichWeb.LayoutAssigns.self_hosted?())

  defp query?(conn), do: conn.query_string == ""
end
