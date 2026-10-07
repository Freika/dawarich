defmodule DawarichWeb.RailsRemoteIpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DawarichWeb.RailsRemoteIp

  test "client identity uses only XFF and Client-IP with Rails proxy filtering spoof checks and configured proxy replacement" do
    mapped = %{Plug.Test.conn(:get, "/") | remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7109}}
    assert RailsRemoteIp.ip(mapped) == "203.0.113.9"
    saved = Application.get_env(:dawarich, :trusted_proxies)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:dawarich, :trusted_proxies, saved),
        else: Application.delete_env(:dawarich, :trusted_proxies)
    end)

    Application.delete_env(:dawarich, :trusted_proxies)
    conn = %{Plug.Test.conn(:get, "/") | remote_ip: {10, 0, 0, 2}}

    forged =
      conn
      |> put_req_header("forwarded", "for=198.51.100.9")
      |> put_req_header("x-real-ip", "198.51.100.8")

    assert RailsRemoteIp.ip(forged) == "10.0.0.2"

    assert RailsRemoteIp.ip(
             put_req_header(forged, "x-forwarded-for", "192.0.2.1, 203.0.113.25, 10.0.0.3")
           ) == "203.0.113.25"

    assert RailsRemoteIp.ip(
             put_req_header(conn, "x-forwarded-for", "invalid, 169.254.1.2, fe80::3")
           ) == "169.254.1.2"

    assert RailsRemoteIp.ip(put_req_header(conn, "x-forwarded-for", "[2001:db8::5]:443, fc00::2")) ==
             "2001:db8::5"

    assert RailsRemoteIp.ip(put_req_header(conn, "client-ip", "192.0.2.1, 203.0.113.26")) ==
             "203.0.113.26"

    spoofed =
      conn
      |> put_req_header("x-forwarded-for", "203.0.113.25")
      |> put_req_header("client-ip", "198.51.100.8")

    assert_raise RailsRemoteIp.IpSpoofAttackError, "IP spoofing attack", fn ->
      RailsRemoteIp.ip(spoofed)
    end

    assert RailsRemoteIp.ip(put_req_header(conn, "x-forwarded-for", "203.0.113.25/24, garbage")) ==
             "10.0.0.2"

    Application.put_env(:dawarich, :trusted_proxies, ["203.0.113.0/24", "2001:db8::/32"])

    assert RailsRemoteIp.ip(
             put_req_header(conn, "x-forwarded-for", "192.0.2.1, 203.0.113.25, 2001:db8::5")
           ) == "192.0.2.1"

    assert RailsRemoteIp.ip(put_req_header(conn, "x-forwarded-for", "192.0.2.1, 10.0.0.3")) ==
             "10.0.0.3"
  end
end
