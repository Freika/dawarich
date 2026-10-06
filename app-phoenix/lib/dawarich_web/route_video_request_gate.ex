defmodule DawarichWeb.RouteVideoRequestGate do
  @moduledoc false

  def actions?(conn, _params), do: query?(conn)

  defp query?(conn), do: conn.query_string == ""
end
