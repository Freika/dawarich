defmodule DawarichWeb.VisitRequestGate do
  @moduledoc false
  alias DawarichWeb.Strangler

  def actions?(conn, _params), do: query?(conn)

  defp query?(conn), do: conn.query_string == ""

  def navigation?(conn, _params) do
    Strangler.page_request?(conn) and
      DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(status locale))
  end
end
