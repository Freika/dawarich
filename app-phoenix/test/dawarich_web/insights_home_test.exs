defmodule DawarichWeb.InsightsHomeTest do
  use ExUnit.Case, async: true
  import Plug.Conn

  test "authenticated preferred-map redirect preserves actual Source absolute URL, empty body and cache policy" do
    conn =
      Plug.Test.conn(
        :get,
        "http://www.example.com/?return_to=https%3A%2F%2Fevil.invalid&year=2024"
      )
      |> DawarichWeb.RailsHeaders.call([])
      |> DawarichWeb.InsightsFrame.call([])
      |> DawarichWeb.InsightsHome.index(%{
        "return_to" => "https://evil.invalid",
        "year" => "2024"
      })

    assert conn.status == 302
    assert conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
  end
end
