defmodule DawarichWeb.PlaceRequestGate do
  @moduledoc false

  def actions?(conn, _params),
    do:
      (DawarichWeb.LayoutAssigns.self_hosted?() or Dawarich.Standalone.enabled?()) and
        query?(conn)

  defp query?(%{query_string: ""}), do: true

  defp query?(%{path_info: ["places", id], method: method} = conn) when method in ~w(POST DELETE),
    do:
      Regex.match?(~r/\A\d{1,18}\z/, id) and
        DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(page))

  defp query?(_), do: false
end
