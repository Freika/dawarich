defmodule DawarichWeb.RackIpTest do
  use ExUnit.Case, async: true

  alias Dawarich.Test.RateLimitCorpus
  alias DawarichWeb.RackIp

  defp conn_from(remote, headers) do
    {:ok, ip} = remote |> String.to_charlist() |> :inet.parse_address()
    %{Plug.Test.conn(:get, "/") | remote_ip: ip, req_headers: Enum.to_list(headers)}
  end

  test "ip is Rack::Request#ip for every recorded REMOTE_ADDR, X-Forwarded-For and Forwarded" do
    for v <- RateLimitCorpus.corpus()["ips"],
        do: assert(RackIp.ip(conn_from(v["remote_addr"], v["headers"])) == v["ip"], inspect(v))
  end

  test "REMOTE_ADDR is the address Phoenix sends to Puma, so an IPv4-mapped peer reads as IPv4" do
    conn = %{Plug.Test.conn(:get, "/") | remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7109}}
    assert RackIp.ip(conn) == "203.0.113.9"
  end
end
