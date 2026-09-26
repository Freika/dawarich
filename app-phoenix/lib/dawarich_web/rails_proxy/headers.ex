defmodule DawarichWeb.RailsProxy.Headers do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  @remote_addr "x-dawarich-remote-addr"
  @hop_by_hop ~w(connection keep-alive proxy-connection te trailer transfer-encoding upgrade expect http2-settings)

  def remote_addr_header, do: @remote_addr

  def request(conn) do
    nominated = Enum.reject(connection_tokens(conn.req_headers), &(&1 == "content-length"))
    dropped = [@remote_addr | @hop_by_hop] ++ nominated
    kept = Enum.reject(conn.req_headers, fn {name, _} -> name in dropped end)
    kept ++ framing(conn) ++ [{@remote_addr, peer(conn.remote_ip)}]
  end

  def response(headers) do
    headers = Enum.map(headers, fn {name, value} -> {String.downcase(name), value} end)
    dropped = @hop_by_hop ++ connection_tokens(headers)
    Enum.reject(headers, fn {name, _} -> name in dropped end)
  end

  def target(%{query_string: ""} = conn), do: conn.request_path
  def target(conn), do: conn.request_path <> "?" <> conn.query_string

  def chunked?(conn), do: get_req_header(conn, "transfer-encoding") != []

  def body?(conn),
    do: chunked?(conn) or Enum.any?(get_req_header(conn, "content-length"), &(&1 != "0"))

  def bodyless?(method, status), do: method == "HEAD" or status in [204, 304]

  def websocket_upgrade?(conn) do
    conn.method == "GET" and "websocket" in tokens(conn.req_headers, "upgrade") and
      "upgrade" in tokens(conn.req_headers, "connection")
  end

  defp framing(conn), do: if(chunked?(conn), do: [{"transfer-encoding", "chunked"}], else: [])

  defp peer({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: peer({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  defp peer(ip), do: ip |> :inet.ntoa() |> to_string()

  defp connection_tokens(headers), do: tokens(headers, "connection")

  defp tokens(headers, name) do
    for {^name, value} <- headers,
        token <- Plug.Conn.Utils.list(value),
        do: String.downcase(token)
  end
end
