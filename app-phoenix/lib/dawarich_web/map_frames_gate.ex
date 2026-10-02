defmodule DawarichWeb.MapFramesGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  def track?(conn, _params), do: plain?(conn, query(conn))

  defp query(conn), do: Plug.Conn.Query.decode(conn.query_string)

  defp plain?(conn, query),
    do:
      not Map.has_key?(query, "locale") and not Map.has_key?(query, "client") and
        get_req_header(conn, "x-dawarich-client") == []
end
