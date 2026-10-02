defmodule DawarichWeb.MapFramesGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.MapWindow
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def track?(conn, _params), do: plain?(conn, query(conn))

  def feed?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and timestamp?(query["start_at"]) and timestamp?(query["end_at"])
  end

  defp timestamp?(value) when is_binary(value),
    do: Ruby.present?(value) and (value =~ ~r/\A\d+\z/ or MapWindow.iso?(value))

  defp timestamp?(_value), do: false

  defp query(conn), do: Plug.Conn.Query.decode(conn.query_string)

  defp plain?(conn, query),
    do:
      not Map.has_key?(query, "locale") and not Map.has_key?(query, "client") and
        get_req_header(conn, "x-dawarich-client") == []
end
