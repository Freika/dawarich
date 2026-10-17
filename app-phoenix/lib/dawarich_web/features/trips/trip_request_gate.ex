defmodule DawarichWeb.TripRequestGate do
  @moduledoc false

  def actions?(conn, _params), do: query?(conn)

  defp query?(%{query_string: ""}), do: true

  defp query?(%{path_info: ["trips", id, "export"], method: "POST"} = conn),
    do:
      Regex.match?(~r/\A\d{1,18}\z/, id) and
        DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(file_format))

  defp query?(_), do: false
end
