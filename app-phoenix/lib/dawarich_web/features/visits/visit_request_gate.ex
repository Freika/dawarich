defmodule DawarichWeb.VisitRequestGate do
  @moduledoc false
  alias DawarichWeb.PageRequest

  def actions?(conn, _params), do: query?(conn)

  defp query?(conn), do: conn.query_string == ""

  def navigation?(conn, _params) do
    PageRequest.page_request?(conn) and
      DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(status locale))
  end
end
