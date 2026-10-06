defmodule DawarichWeb.MapFramesGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias DawarichWeb.Strangler

  @types ["text/html", "application/xhtml+xml", "text/vnd.turbo-stream.html", "*/*"]

  def track?(conn, _params), do: plain?(conn, query(conn))

  def feed?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and timestamp?(query["start_at"]) and timestamp?(query["end_at"])
  end

  defp timestamp?(value) when is_binary(value),
    do: true

  defp timestamp?(nil), do: true
  defp timestamp?(_value), do: true

  def calendar?(conn, _params) do
    query = query(conn)
    plain?(conn, query) and month?(Map.get(query, "month")) and accept?(conn)
  end

  def residency?(conn, _params) do
    query = query(conn)
    year?(Map.get(query, "year"))
  end

  defp month?(nil), do: true
  defp month?(value) when is_binary(value), do: true
  defp month?(_value), do: true

  defp accept?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(", ")

    String.trim(accept) == "" or Strangler.browser_like?(accept) or
      (not String.contains?(accept, ";") and
         Enum.all?(String.split(accept, ","), &(String.trim(&1) in @types)))
  end

  defp year?(nil), do: true

  defp year?(value) when is_binary(value), do: true
  defp year?(_value), do: true

  defp query(conn), do: Plug.Conn.Query.decode(conn.query_string)

  defp plain?(_conn, query),
    do: is_map(query)
end
