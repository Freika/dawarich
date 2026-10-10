defmodule DawarichWeb.VisitsNavigationTest do
  use Dawarich.IngestCase, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  @endpoint DawarichWeb.Endpoint

  test "default visits navigation is a public 302 with Rails Location" do
    for method <- [:get, :head] do
      conn = dispatch(build_conn(), @endpoint, method, "/visits", nil)
      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               "http://www.example.com/map/v2?panel=timeline&date=today&status=confirmed"
             ]

      assert conn.resp_body == ""
      assert get_resp_header(conn, "set-cookie") == []
    end
  end

  test "explicit empty visits status is not replaced with confirmed" do
    for status <- ["", "suggested", "declined"] do
      conn = get(build_conn(), "/visits?status=" <> status)
      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               "http://www.example.com/map/v2?panel=timeline&date=today&status=" <> status
             ]
    end

    for query <- [
          "status[]=suggested",
          "status[x]=suggested",
          "status=a&status=b",
          "status=%xx",
          "status=%FF"
        ] do
      refute DawarichWeb.A8Gate.navigation?(Plug.Test.conn(:get, "/visits?" <> query), %{})
    end
  end
end
