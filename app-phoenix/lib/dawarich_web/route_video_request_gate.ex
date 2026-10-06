defmodule DawarichWeb.RouteVideoRequestGate do
  @moduledoc false

  def actions?(conn, _params), do: DawarichWeb.LayoutAssigns.self_hosted?() and query?(conn)

  defp query?(conn), do: conn.query_string == ""
end
